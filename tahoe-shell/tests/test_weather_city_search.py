#!/usr/bin/env python3
"""Weather city geocoding search (China-friendly Open-Meteo)."""

from __future__ import annotations

import unittest
from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[1]
WEATHER = SHELL_ROOT / "services" / "Weather.qml"
WEATHER_PAGE = SHELL_ROOT / "components" / "settings" / "pages" / "WeatherPage.qml"


class WeatherCitySearchTests(unittest.TestCase):
    def test_weather_service_geocode_api(self) -> None:
        text = WEATHER.read_text(encoding="utf-8")
        self.assertIn("geocoding-api.open-meteo.com/v1/search", text)
        self.assertIn("function searchLocations(query)", text)
        self.assertIn("function selectSearchResult(index)", text)
        self.assertIn("function normalizeGeocodeResults(payload)", text)
        self.assertIn('"language": "zh"', text)
        self.assertIn("locationSearchResults", text)
        self.assertIn("id: geocodeProcess", text)
        # Prefer CN results for Chinese city queries.
        self.assertIn('countryCode || "").toUpperCase() === "CN"', text)

    def test_weather_page_city_search_ui(self) -> None:
        text = WEATHER_PAGE.read_text(encoding="utf-8")
        self.assertIn("搜索城市", text)
        self.assertIn("function searchCityNow()", text)
        self.assertIn("function selectSearchResult(index)", text)
        self.assertIn("page.searchResults", text)
        self.assertIn("选用", text)
        self.assertIn("北京、杭州、成都", text)


if __name__ == "__main__":
    unittest.main()
