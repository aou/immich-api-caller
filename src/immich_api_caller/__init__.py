import requests
from dotenv import dotenv_values

config = dotenv_values()

if "IMMICH_API_KEY" not in config.keys():
    raise ValueError("IMMICH_API_KEY not defined in environment")
