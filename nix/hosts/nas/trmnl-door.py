"""Feed the TRMNL door screen, laid out as a newspaper front page.

Runs from a systemd timer (larapaper.nix). Gathers Angus's calendar (the
trmnl-calendar service account), the Windrush line at Canonbury (TfL's open
API), the weather (Open-Meteo, no key) and, once Miniflux exists, the latest
headlines; then replaces the payload of the "Door" webhook plugin in
LaraPaper, which renders it to the device.

Inputs:
  stdin                    the service account key JSON (from 1Password)
  TRMNL_DOOR_WEBHOOK       LaraPaper webhook URL for the Door plugin
  MINIFLUX_URL, MINIFLUX_TOKEN   optional; no headlines section without them
"""

import datetime as dt
import json
import os
import sys
from zoneinfo import ZoneInfo

import requests
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

LONDON = ZoneInfo("Europe/London")
CALENDAR_ID = "angusbuick@gmail.com"
CANONBURY = "910GCNNB"
LINE = "windrush"
# Line statuses shown on the screen: the Windrush from the door, and the
# Victoria from Highbury & Islington.
STATUS_LINES = ["windrush", "victoria"]

# Highbury & Islington is the northern terminus; every other Windrush train
# from Canonbury is heading south.
NORTH_TERMINUS = "Highbury & Islington"
# Enough to fill the column when there are no headlines; the template
# shows fewer when there are.
MAX_EVENTS = 10
CALENDAR_DAYS = 7
MAX_DEPARTURES = 4
MAX_HEADLINES = 5

# Canonbury, for Open-Meteo.
LAT, LON = 51.5487, -0.0921
RAIN_LIKELY = 50  # percent

# WMO weather codes, as Open-Meteo reports them.
WMO = {
    0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Overcast",
    45: "Fog", 48: "Freezing fog",
    51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle",
    56: "Freezing drizzle", 57: "Freezing drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain",
    66: "Freezing rain", 67: "Freezing rain",
    71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
    80: "Showers", 81: "Showers", 82: "Heavy showers",
    85: "Snow showers", 86: "Snow showers",
    95: "Thunderstorms", 96: "Thunderstorms, hail", 99: "Thunderstorms, hail",
}


def calendar(key: dict, now: dt.datetime) -> list[dict]:
    creds = service_account.Credentials.from_service_account_info(
        key, scopes=["https://www.googleapis.com/auth/calendar.readonly"]
    )
    start_of_day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    r = AuthorizedSession(creds).get(
        f"https://www.googleapis.com/calendar/v3/calendars/{CALENDAR_ID}/events",
        params={
            "timeMin": now.isoformat(),
            "timeMax": (start_of_day + dt.timedelta(days=CALENDAR_DAYS)).isoformat(),
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": 25,
        },
        timeout=20,
    )
    r.raise_for_status()

    today = now.date()
    events = []
    for item in r.json().get("items", []):
        if item.get("status") == "cancelled" or any(
            a.get("self") and a.get("responseStatus") == "declined"
            for a in item.get("attendees", [])
        ):
            continue
        start = item["start"]
        if "date" in start:
            day = dt.date.fromisoformat(start["date"])
            time = "All day"
        else:
            when = dt.datetime.fromisoformat(start["dateTime"]).astimezone(LONDON)
            day = when.date()
            time = when.strftime("%H:%M")
        events.append(
            {
                "day": (
                    "Today" if day <= today
                    else "Tomorrow" if day == today + dt.timedelta(days=1)
                    else day.strftime("%A")
                ),
                "time": time,
                "title": item.get("summary", "(busy)"),
                "where": (item.get("location") or "").split(",")[0],
            }
        )
    return events[:MAX_EVENTS]


def line_statuses() -> list[dict]:
    r = requests.get(
        f"https://api.tfl.gov.uk/Line/{','.join(STATUS_LINES)}/Status", timeout=20
    )
    r.raise_for_status()
    by_id = {line["id"]: line for line in r.json()}
    out = []
    for line_id in STATUS_LINES:
        line = by_id[line_id]
        worst = min(line["lineStatuses"], key=lambda s: s["statusSeverity"])
        reason = (worst.get("reason") or "").strip()
        # TfL prefixes every reason with the line name, which the row
        # already shows: "WINDRUSH LINE: Minor delays ..."
        if ":" in reason[:30]:
            reason = reason.split(":", 1)[1].strip()
        out.append({
            "name": line["name"],
            "status": worst["statusSeverityDescription"],
            "good": worst["statusSeverity"] == 10,
            "reason": reason,
        })
    return out


def windrush(now: dt.datetime) -> dict:

    # The line-scoped endpoint, not /StopPoint/{id}/Arrivals: on 2026-11-04 the
    # stop-wide one returned an empty list for minutes while this one had trains.
    arrivals = requests.get(
        f"https://api.tfl.gov.uk/Line/{LINE}/Arrivals/{CANONBURY}", timeout=20
    )
    arrivals.raise_for_status()

    north, south = [], []
    for a in sorted(arrivals.json(), key=lambda a: a["timeToStation"]):
        if a["lineId"] != LINE:
            continue
        dest = a["destinationName"].removesuffix(" Rail Station")
        # Absolute times, not "in 3 min": the screen can sit for 15 minutes,
        # and a clock time stays true while a countdown goes stale.
        when = (now + dt.timedelta(seconds=a["timeToStation"])).strftime("%H:%M")
        bucket = north if dest == NORTH_TERMINUS else south
        if len(bucket) < MAX_DEPARTURES:
            bucket.append({"time": when, "dest": dest})

    return {"north": north, "south": south}


def icon(code: int, is_day: int) -> str:
    """The template's icon class for a WMO code: sun, moon, cloud, rain..."""
    if code in (0, 1):
        return "sun" if is_day else "moon"
    if code == 2:
        return "cloud-sun" if is_day else "cloud-moon"
    if code == 3:
        return "cloud"
    if code in (45, 48):
        return "fog"
    if code in (51, 53, 55, 56, 57):
        return "drizzle"
    if code in (71, 73, 75, 77, 85, 86):
        return "snow"
    if code >= 95:
        return "storm"
    return "rain"


def weather(now: dt.datetime) -> dict:
    r = requests.get(
        "https://api.open-meteo.com/v1/forecast",
        params={
            "latitude": LAT,
            "longitude": LON,
            "current": "temperature_2m,weather_code,is_day",
            "hourly": "precipitation_probability,temperature_2m,weather_code,is_day",
            "forecast_hours": 12,
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunset",
            "timezone": "Europe/London",
            "forecast_days": 1,
        },
        timeout=20,
    )
    r.raise_for_status()
    d = r.json()

    # The first hour from now when rain is more likely than not.
    rain_from = ""
    hourly = d["hourly"]
    for when, chance in zip(hourly["time"], hourly["precipitation_probability"]):
        hour = dt.datetime.fromisoformat(when).replace(tzinfo=LONDON)
        if hour >= now.replace(minute=0, second=0, microsecond=0) and (chance or 0) >= RAIN_LIKELY:
            rain_from = hour.strftime("%H:%M")
            break

    # Every other hour for the next ten, for the strip under the headline figure.
    hours = []
    for when, temp, code, chance, is_day in zip(
        hourly["time"], hourly["temperature_2m"], hourly["weather_code"],
        hourly["precipitation_probability"], hourly["is_day"],
    ):
        hour = dt.datetime.fromisoformat(when).replace(tzinfo=LONDON)
        if hour > now and hour.hour % 2 == 0 and len(hours) < 5:
            hours.append({"time": hour.strftime("%H"), "temp": round(temp),
                          "rain": chance or 0, "icon": icon(code, is_day)})

    return {
        "now": round(d["current"]["temperature_2m"]),
        "hours": hours,
        "sunset": d["daily"]["sunset"][0][-5:],
        "summary": WMO.get(d["current"]["weather_code"], ""),
        "icon": icon(d["current"]["weather_code"], d["current"]["is_day"]),
        "high": round(d["daily"]["temperature_2m_max"][0]),
        "low": round(d["daily"]["temperature_2m_min"][0]),
        "rain_chance": d["daily"]["precipitation_probability_max"][0] or 0,
        "rain_from": rain_from,
    }


def headlines() -> list[dict]:
    url, token = os.environ.get("MINIFLUX_URL"), os.environ.get("MINIFLUX_TOKEN")
    if not (url and token):
        return []
    r = requests.get(
        f"{url.rstrip('/')}/v1/entries",
        headers={"X-Auth-Token": token},
        params={"status": "unread", "order": "published_at", "direction": "desc",
                "limit": MAX_HEADLINES},
        timeout=20,
    )
    r.raise_for_status()
    return [
        {"title": e["title"], "source": e["feed"]["title"]}
        for e in r.json().get("entries", [])
    ]


def main() -> None:
    key = json.load(sys.stdin)
    now = dt.datetime.now(LONDON)

    payload = {
        "updated": now.strftime("%H:%M"),
        "date": now.strftime("%A %-d %B %Y"),
        "headlines": headlines(),
        "events": calendar(key, now),
        "weather": weather(now),
        "windrush": windrush(now),
        "lines": line_statuses(),
    }

    r = requests.post(
        os.environ["TRMNL_DOOR_WEBHOOK"],
        json={"merge_variables": payload},
        timeout=20,
    )
    r.raise_for_status()
    print(
        f"pushed {len(payload['events'])} events; "
        + ", ".join(f"{l['name']} {l['status']}" for l in payload["lines"])
    )


if __name__ == "__main__":
    main()
