import os
import unittest
from unittest.mock import patch

import check_pages_deployment as check


class PagesDeploymentTests(unittest.TestCase):
    def test_git_auto_deployment_must_be_explicitly_disabled(self):
        for config in ({}, {"production_deployments_enabled": True}):
            with self.subTest(config=config), self.assertRaises(ValueError):
                check.validate_project({"production_branch": "main", "source": {"config": config}})
        check.validate_project({"production_branch": "main", "source": {
            "config": {"production_deployments_enabled": False}}})

    def test_direct_upload_project_and_production_branch(self):
        check.validate_project({"production_branch": "main", "source": None})
        with self.assertRaises(ValueError):
            check.validate_project({"production_branch": "other"})

    def test_missing_configuration_reports_names_only(self):
        with patch.dict(os.environ, {"SUPABASE_URL": "dummy-value"}, clear=True):
            with self.assertRaises(ValueError) as error:
                check.main()
            self.assertIn("GOOGLE_MAPS_WEB_KEY", str(error.exception))
            self.assertIn("CLOUDFLARE_API_TOKEN", str(error.exception))
            self.assertNotIn("dummy-value", str(error.exception))

    def test_incomplete_git_source_configuration_blocks_deployment(self):
        for source in ({}, {"config": None}, "unknown"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                check.validate_project({"production_branch": "main", "source": source})
