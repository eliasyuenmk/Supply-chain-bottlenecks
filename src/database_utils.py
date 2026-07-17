# src/database_utils.py
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Find the .env file in the root directory and load its variables into memory
load_dotenv()

def get_db_engine():
    """
    Creates and returns a SQLAlchemy engine using secured environment variables.
    """
    DB_TYPE = 'postgresql'
    DB_DRIVER = 'psycopg2'
    
    # Safely fetch credentials from local environment memory
    DB_USER = os.getenv('DB_USER')
    DB_PASS = os.getenv('DB_PASS')
    DB_HOST = os.getenv('DB_HOST')
    DB_PORT = os.getenv('DB_PORT')
    DB_NAME = os.getenv('DB_NAME')
    
    # Build the connection string dynamically
    connection_string = f"{DB_TYPE}+{DB_DRIVER}://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
    return create_engine(connection_string)

def init_staging_schema(engine):
    """
    Ensures the 'staging' schema exists in PostgreSQL before data loading.
    """
    with engine.connect() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS staging;"))
        conn.commit()