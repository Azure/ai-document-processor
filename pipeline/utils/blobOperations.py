from dataclasses import dataclass
from configuration import Configuration
config = Configuration()

@dataclass
class BlobMetadata:
    name: str
    url: str
    container: str

    def to_dict(self):
        return {"name": self.name, "url": self.url, "container": self.container}
    
class AzureBlobStorageService:
    def __init__(self):
        self.account_name = config.get_value("STORAGE_ACCOUNT_NAME")