"""Exceptions labctl turns into an error message and an exit code."""


class LabctlError(Exception):
    exit_code = 1


class ConfigError(LabctlError):
    exit_code = 2


class ApiError(LabctlError):
    def __init__(self, status: int, message: str):
        super().__init__(f"API returned {status}: {message}")
        self.status = status


class NotFound(ApiError):
    exit_code = 4
