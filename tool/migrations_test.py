"""Catch migration-history collisions before a managed deployment."""
from collections import defaultdict
from pathlib import Path
import unittest


class MigrationHistoryTests(unittest.TestCase):
    def test_migration_versions_are_unique(self):
        versions = defaultdict(list)
        root = Path(__file__).resolve().parents[1] / 'supabase/migrations'
        for path in root.glob('*.sql'):
            versions[path.name.split('_', 1)[0]].append(path.name)
        duplicates = {version: names for version, names in versions.items()
                      if len(names) > 1}
        self.assertFalse(duplicates, f'Duplicate Supabase migration versions: {duplicates}')
