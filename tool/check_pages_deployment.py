"""Validate build inputs and prevent competing Cloudflare Git deployments."""
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


def validate_project(project):
    if project.get("production_branch") != "main":
        raise ValueError("Set the Cloudflare Pages production branch to main.")
    source = project.get("source")
    if source and source.get("config", {}).get("production_deployments_enabled") is not False:
        raise ValueError(
            "Disable automatic production branch deployments in Cloudflare Pages "
            "before deploying through GitHub Actions."
        )


def main():
    required = (
        "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "GOOGLE_MAPS_WEB_KEY",
        "SUPPORT_EMAIL", "CLOUDFLARE_PAGES_PROJECT", "CLOUDFLARE_ACCOUNT_ID",
        "CLOUDFLARE_API_TOKEN",
    )
    missing = [name for name in required if not os.getenv(name, "").strip()]
    if missing:
        raise ValueError("Missing GitHub environment configuration: " + ", ".join(missing))
    if (os.getenv("DEPLOY_ENVIRONMENT") == "staging"
            and os.environ["CLOUDFLARE_PAGES_PROJECT"] != "chairside-staging"):
        raise ValueError("Set staging CLOUDFLARE_PAGES_PROJECT to chairside-staging.")
    account = quote(os.environ["CLOUDFLARE_ACCOUNT_ID"], safe="")
    project = quote(os.environ["CLOUDFLARE_PAGES_PROJECT"], safe="")
    request = Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/pages/projects/{project}",
        headers={"Authorization": "Bearer " + os.environ["CLOUDFLARE_API_TOKEN"]},
    )
    try:
        with urlopen(request, timeout=30) as response:
            result = json.load(response)
    except HTTPError as error:
        raise ValueError(f"Cloudflare project lookup failed (HTTP {error.code}). Check account, project and token permissions.") from None
    except (URLError, TimeoutError):
        raise ValueError("Cloudflare project lookup failed; check network connectivity.") from None
    if not result.get("success") or not isinstance(result.get("result"), dict):
        raise ValueError("Cloudflare project lookup did not return a valid project.")
    validate_project(result["result"])
    print("Web build configuration present; no competing automatic main deployment configured.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
