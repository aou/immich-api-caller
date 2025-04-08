import requests
from dotenv import dotenv_values

config = dotenv_values()

if "IMMICH_API_KEY" not in config.keys():
    raise ValueError("IMMICH_API_KEY not defined in environment")


baseurl = "http://localhost:2283"

endpoint = "/api/albums"

url = baseurl + endpoint

payload = {}
headers = {"Accept": "application/json", "x-api-key": config["IMMICH_API_KEY"]}

response = requests.request("GET", url, headers=headers, data=payload)
