"""HTTP client for the lab management API."""

import functools
import logging
import time

import requests

from .errors import ApiError, NotFound

log = logging.getLogger(__name__)

RETRY_STATUS = {502, 503, 504}


def retry(times: int = 3, delay: float = 2.0):
    """Retries a call that failed with a connection error or a gateway status."""
    def wrap(fn):
        @functools.wraps(fn)
        def inner(*args, **kwargs):
            for attempt in range(1, times + 1):
                try:
                    return fn(*args, **kwargs)
                except requests.ConnectionError as err:
                    if attempt == times:
                        raise ApiError(0, str(err)) from None
                except ApiError as err:
                    if err.status not in RETRY_STATUS or attempt == times:
                        raise
                log.warning("attempt %d failed, retrying in %.0fs", attempt, delay)
                time.sleep(delay)
        return inner
    return wrap


class LabClient:
    def __init__(self, host: str, token: str, verify: bool = True, timeout: int = 15):
        self.base = host.rstrip("/") + "/api/v1"
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {token}"
        self.session.verify = verify

    def _check(self, resp: requests.Response):
        if resp.status_code == 404:
            raise NotFound(404, resp.url)
        if resp.status_code >= 400:
            raise ApiError(resp.status_code, resp.text[:200])
        return resp.json() if resp.content else None

    @retry()
    def get(self, path: str, **params):
        log.debug("GET %s %s", path, params)
        return self._check(self.session.get(self.base + path, params=params, timeout=self.timeout))

    @retry()
    def post(self, path: str, body: dict):
        log.debug("POST %s", path)
        return self._check(self.session.post(self.base + path, json=body, timeout=self.timeout))

    def delete(self, path: str):
        log.debug("DELETE %s", path)
        return self._check(self.session.delete(self.base + path, timeout=self.timeout))

    # Convenience wrappers the commands use.
    def vms(self, host=None):
        return self.get("/vms", host=host) if host else self.get("/vms")

    def vm_action(self, name: str, action: str):
        return self.post(f"/vms/{name}/{action}", {})

    def wait_for_job(self, job_id: str, timeout: int = 600):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            job = self.get(f"/jobs/{job_id}")
            if job["state"] in ("done", "failed"):
                return job
            time.sleep(5)
        raise ApiError(0, f"job {job_id} still running after {timeout}s")
