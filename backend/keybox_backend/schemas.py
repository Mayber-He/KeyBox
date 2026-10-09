import base64
import binascii
from typing import Literal
from uuid import UUID

from pydantic import Field, StrictBool, StrictInt, field_validator, model_validator

from .auth import StrictModel


def decode_base64(value, minimum, maximum):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        raise ValueError('Invalid base64')
    if base64.b64encode(decoded).decode('ascii') != value or not minimum <= len(decoded) <= maximum:
        raise ValueError('Invalid encoded length or noncanonical base64')
    return value


class Envelope(StrictModel):
    version: StrictInt = Field(ge=1, le=1)
    nonce: str = Field(max_length=16)
    ciphertext: str = Field(max_length=1398104)
    tag: str = Field(max_length=24)

    @field_validator('nonce')
    @classmethod
    def nonce_length(cls, value):
        return decode_base64(value, 12, 12)

    @field_validator('tag')
    @classmethod
    def tag_length(cls, value):
        return decode_base64(value, 16, 16)

    @field_validator('ciphertext')
    @classmethod
    def ciphertext_length(cls, value):
        return decode_base64(value, 1, 1024 * 1024)


class Kdf(StrictModel):
    algorithm: Literal['argon2id']
    memory_kib: StrictInt = Field(ge=65536, le=65536)
    iterations: StrictInt = Field(ge=3, le=3)
    parallelism: StrictInt = Field(ge=4, le=4)
    salt: str = Field(max_length=24)

    @field_validator('salt')
    @classmethod
    def salt_length(cls, value):
        return decode_base64(value, 16, 16)


class Metadata(StrictModel):
    format_version: StrictInt = Field(ge=1, le=1)
    vault_id: UUID
    kdf: Kdf
    password_wrap: Envelope
    recovery_wrap: Envelope


class MetadataWrite(StrictModel):
    base_version: StrictInt = Field(ge=0)
    operation_id: UUID
    payload: Metadata


class ItemWrite(StrictModel):
    vault_id: UUID
    base_version: StrictInt = Field(ge=0)
    operation_id: UUID
    payload: Envelope | None
    deleted: StrictBool

    @model_validator(mode='after')
    def payload_matches_deletion(self):
        if self.deleted != (self.payload is None):
            raise ValueError('Deletion requires null payload; active items require ciphertext')
        return self
