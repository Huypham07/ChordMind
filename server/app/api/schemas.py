from pydantic import BaseModel

class SubmitRequest(BaseModel):
    url: str

# ponytail: the domain AnalysisResult IS the response contract (returned via to_dict);
# no duplicate Pydantic response model to keep in sync.
