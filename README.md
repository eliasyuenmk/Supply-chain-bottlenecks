# End-to-End E-Commerce Supply Chain & Customer Sentiment Dashboard

## Key Business Insights Uncovered
- The Delivery Cliff: Analyzing Page 3's Impact Curve reveals that customer review scores drop exponentially once a shipping delay exceeds 2.1 days past promise, dropping the average feedback rating from $4.3$ to $1.8$ stars.
- Seller-Driven Bottlenecks: Page 2 isolates that sellers based in specific geographic regions take an average of $4.8$ days simply to process and hand over packages to local carriers—proving the primary bottleneck lies in warehousing dispatch rather than regional courier transit.
- Volumetric Capacity Risk: The scatter plot mathematically isolates heavy categories (e.g., Furniture, Large Appliances) as the main drivers of carrier delay, suggesting that offering localized, specialized shipping partners for oversized products could mitigate systemic delivery overruns.

## Setup Instructions:
1. Clone the repository.
2. Copy .env.example to a new file named .env and fill in your local PostgreSQL credentials.

## Project Overview:
This enterprise-grade, 3-page Power BI dashboard analyzes logistics performance, identifies supply chain bottlenecks, and correlates delivery latencies directly with customer sentiment (review scores). Developed using a structured Star Schema and advanced analytical DAX modeling, this tool serves as a strategic and operational decision-making framework for e-commerce executive leadership.

![Dashboard Page 1](images/dashboard_page1.png)

![Dashboard Page 2](images/dashboard_page2.png)

![Dashboard Page 3](images/dashboard_page3.png)

## The Business Problem:
Logistics and fulfillment friction directly threaten brand retention and bottom-line revenue. However, businesses frequently treat supply chain metrics and customer experience feedback as isolated data silos.

## The Goal: 
Build an integrated analytics suite that quantifies how physical bottlenecks (processing delays, carrier transit times, product weight/volume dimensions) impact customer star ratings, and isolate high-risk regional routes and sellers.

## 3-Page Analytical Architecture:
The dashboard is structured using a Top-Down (Macro-to-Micro) Analytical Framework:

### Page 1: Executive Sales & Delivery Performance Overview
- Target Audience: C-Suite Executives & Regional Directors.
- Core Focus: High-level macroeconomic health of the business. Includes revenue performance, monthly order volumes, and aggregate On-Time Delivery Rates (OTD%).
- Key Design Highlight: Custom dynamic inline SVG sparklines built into the KPI cards to show historic metric trends directly inside the primary numeric containers.

### Page 2: Fulfillment Logistics & Supply Chain Bottleneck Diagnostics
- Target Audience: Logistics Managers & Supply Chain Coordinators.
- Core Focus: Isolating the physical phases of fulfillment latency.
- Key Design Highlight: A custom chronological step-ladder milestone chart to track time spent at the seller’s warehouse vs. carrier transit, alongside a multi-variable scatter plot correlating physical package volume ($\text{cm}^3$) with delivery duration to pinpoint capacity strain.

### Page 3: Customer Sentiment Impact & Operational Risk Analysis
- Target Audience: Vendor Management & Customer Experience (CX) Teams.
- Core Focus: Quantifying the direct impact of late deliveries on brand reputation.
- Key Design Highlight: A dual-axis "Impact Curve" chart tracking delivery variance days against review scores, accompanied by a dynamic seller-level risk matrix to pinpoint exactly which vendors are driving down customer satisfaction.

## Technical Highlights & DAX Engineering
### Dynamic Inline SVG Sparklines (Page 1 Cards)
To bypass the limitations of basic native card visuals, custom line vectors were drawn dynamically using DAX text-concatenation inside a virtualized date table. The image_tag output is categorized as an Image URL to render a high-performance vector trendline directly within the card background.

```
sparkline_total_revenue = 
// Static line color 
VAR LineColour = "#2C3E50"
VAR PointColour = "white"
VAR Defs = "<defs>
    <linearGradient id='grad' x1='0' y1='25' x2='0' y2='50' gradientUnits='userSpaceOnUse'>
        <stop stop-color='%23666666' offset='0' />
        <stop stop-color='%23CCCCCC' offset='0.3' />
        <stop stop-color='white' offset='1' />
    </linearGradient>
</defs>"

// "Date" field used in this example along the X axis
VAR XMinDate = MIN('analytics vw_executive_overview'[date])
VAR XMaxDate = MAX('analytics vw_executive_overview'[date])

// Obtain overall min and overall max measure values when evaluated for each date
VAR YMinValue = MINX(Values('analytics vw_executive_overview'[date]),CALCULATE([total_revenue]))
VAR YMaxValue = MAXX(Values('analytics vw_executive_overview'[date]),CALCULATE([total_revenue]))

// Build table of X & Y coordinates and fit to 50 x 150 viewbox
VAR SparklineTable = ADDCOLUMNS(
    SUMMARIZE('analytics vw_executive_overview','analytics vw_executive_overview'[date]),
        "X",INT(150 * DIVIDE('analytics vw_executive_overview'[date] - XMinDate, XMaxDate - XMinDate)),
        "Y",INT(50 * DIVIDE([total_revenue] - YMinValue,YMaxValue - YMinValue)))

// Concatenate X & Y coordinates to build the sparkline
VAR Lines = CONCATENATEX(SparklineTable,[X] & "," & 50-[Y]," ", 'analytics vw_executive_overview'[date])


// Last data points on the line
VAR LastSparkYValue = MAXX( FILTER(SparklineTable, 'analytics vw_executive_overview'[date]= XMaxDate), [Y])
VAR LastSparkXValue = MAXX( FILTER(SparklineTable, 'analytics vw_executive_overview'[date] = XMaxDate), [X])

// Add to SVG, and verify Data Category is set to Image URL for this measure
VAR SVGImageURL = "data:image/svg+xml;utf8," & 
        --- gradient---
    "<svg xmlns='http://www.w3.org/2000/svg' x='0px' y='0px' viewBox='-7 -7 164 64'>" & Defs & 
     "<polyline fill='url(%23grad)' fill-opacity='0.3' stroke='transparent' 
      stroke-width='0' points=' 0 50 " & Lines & 
      " 150 150 Z '/>" &
    --- Lines---
    "<polyline 
        fill='transparent' stroke='" & LineColour & "' 
        stroke-linecap='round' stroke-linejoin='round' 
        stroke-width='1' points=' " & Lines & 
      " '/>" &
    --- Last Point---
    "<circle cx='"& LastSparkXValue & "' cy='" & 50 - LastSparkYValue & "' r='3' stroke='" & LineColour & "' stroke-width='2' fill='" & PointColour & "' />" &
    "</svg>"

RETURN SVGImageURL
```

### Disconnected Milestone Table for Waterfall Flow (Page 2)
To build a cumulative, multi-measure waterfall chart mapping independent logistics phases (Processing $\rightarrow$ Transit), a disconnected helper dimension was created. The measures are dynamically swapped in at query time using a SWITCH block:

```
waterfall_days = 
SWITCH(
    SELECTEDVALUE('_fulfillment_steps'[StepIndex]),
    1, [avg_seller_processing_time],
    2, [avg_carrier_transit_time],
    BLANK()
)
```

### Customer Negative Review Rate (Page 3 Card)
Calculates the exact ratio of active brand detractors (1 and 2-star reviews) using a robust, divide-by-zero-safe expression:

```
negative_review_rate = 
DIVIDE(
    CALCULATE(
        COUNT('analytics vw_customer_sentiment'[review_score]),
        'analytics vw_customer_sentiment'[review_score] IN { 1, 2 }
    ),
    COUNT('analytics vw_customer_sentiment'[review_score]),
    0
)
```

## Data Model & Design Choices
- Star Schema Architecture: Highly optimized model consisting of clean dimensional layers (Sellers, Customers, Products, Geography, Calendar) surrounding central transactional fact tables.

- Cross-Filtering Integrity: A custom bidirectional bridging table (_Order_Bridge) was designed to resolve granularity mismatches, allowing users to slice sentiment metrics seamlessly across shipping lanes and transit nodes.

- Professional UI/UX Design System:
    - Canvas Layout: Soft off-white background (#F8F9FA) paired with rounded-corner container cards (#FFFFFF) to mimic a sleek, modern web application.
    - Muted Color Semantics: Strict usage of high-contrast, low-saturation corporate tones. Red and orange color rules are locked exclusively to extreme risk parameters (e.g., severe delivery variance, negative review spikes) to optimize visual parsing speed.
