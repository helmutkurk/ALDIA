"""The OpenAPI structures this installer consumes from FastAPI.

Other generated keys are preserved in place. Schema bodies and synthetic example
values remain opaque where the installer only copies them.
"""

from typing import NotRequired, TypedDict


class FieldSchema(TypedDict, total=False):
    description: str
    examples: list[object]
    enum: list[object]


class Component(TypedDict, total=False):
    properties: dict[str, FieldSchema]


class MediaType(TypedDict, total=False):
    schema: object
    example: object


class Response(TypedDict):
    description: str
    content: NotRequired[dict[str, MediaType]]
    headers: NotRequired[dict[str, object]]


Parameter = TypedDict(
    "Parameter",
    {
        "name": str,
        "in": NotRequired[str],
        "required": NotRequired[bool],
        "description": NotRequired[str],
        "schema": NotRequired[object],
        "example": NotRequired[object],
    },
)


class RequestBody(TypedDict):
    required: NotRequired[bool]
    content: dict[str, MediaType]


class Operation(TypedDict):
    responses: dict[str, Response]
    parameters: NotRequired[list[Parameter]]
    requestBody: NotRequired[RequestBody]
    security: NotRequired[list[dict[str, list[str]]]]
    tags: NotRequired[list[str]]
    summary: NotRequired[str]
    description: NotRequired[str]


class Components(TypedDict, total=False):
    schemas: dict[str, Component]
    securitySchemes: dict[str, object]


class Document(TypedDict):
    paths: dict[str, dict[str, Operation]]
    components: NotRequired[Components]
    tags: NotRequired[list[dict[str, str]]]
