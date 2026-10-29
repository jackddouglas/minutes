import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("configuration", Path(__file__).with_name("configure-updates.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ConfigurationTests(unittest.TestCase):
    def test_requires_secure_feed(self):
        for url in ["http://example.com/feed", "https://", "https://user:secret@example.com/feed"]:
            with self.assertRaises(ValueError):
                module.configuration({"MINUTES_UPDATE_FEED_URL": url})

    def test_release_requires_valid_version_and_build(self):
        for env in [{"MINUTES_RELEASE_BUILD": "1"}, {"MINUTES_VERSION": "0.1.11"},
                    {"MINUTES_VERSION": "../bad", "MINUTES_BUILD_NUMBER": "12"},
                    {"MINUTES_VERSION": "0.1.11", "MINUTES_BUILD_NUMBER": "0"}]:
            with self.assertRaises(ValueError):
                module.configuration(env)

    def test_stamps_security_policy_and_version(self):
        settings = module.configuration({"MINUTES_RELEASE_BUILD": "1",
            "MINUTES_VERSION": "0.1.11", "MINUTES_BUILD_NUMBER": "12"})
        self.assertEqual(settings["CFBundleVersion"], "12")
        self.assertEqual(settings["CFBundleShortVersionString"], "0.1.11")
        self.assertTrue(settings["SURequireSignedFeed"])
        self.assertTrue(settings["SUVerifyUpdateBeforeExtraction"])
        self.assertFalse(settings["SUAllowsAutomaticUpdates"])

if __name__ == "__main__":
    unittest.main()
