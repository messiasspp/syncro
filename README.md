# Syncro

> Intelligent, rule-based calendar scheduling for Google Calendar and Apple Calendar with collision-free slot optimization.

## Overview

**Syncro** is a cross-platform scheduling engine and application built with Flutter. It automatically allocates optimal dates and times for personal events and professional/clinical research protocols without scheduling collisions.

### Key Capabilities

- **Smart Rule Engine:** Configurable time windows, work/personal boundaries (`work_hours_only`, `outside_work_hours`, `both_flexible`), duration ranges, and pre/post-buffers.
- **Protocol Roadmaps & Cascading:** Supports long-term sequences (e.g. 1-year clinical research studies with 24 visits) that automatically cascade and recalculate downstream appointments when an earlier date shifts.
- **Hybrid Calendar Sync:** Direct integration with native device calendars (iOS EventKit / Android CalendarProvider) for zero-setup local sync, with cloud API capabilities for desktop.
- **Entity Overrides:** Custom participant preferences (e.g., specific friend or patient constraints) that override default Event Type rules.
- **Instant Messaging:** 1-tap WhatsApp, SMS, and Email confirmation templates.
- **Dual Localization:** Full English and Portuguese (pt-BR) support with 12h/24h time formatting.

---

## Architecture & Documentation

For the complete architectural design, entity-relationship diagrams, interval scheduling algorithms, and rollout phases, see:
📖 **[SPECIFICATION.md](file:///home/msz/Development/syncro/SPECIFICATION.md)**

---

## Seed / Demo Scenarios

The project includes two pre-configured scenarios for testing and demonstration:

1. **Friends Zone (Personal):**
   - Entity: **Mendy**
   - Rule: Outside work hours, Thursday evenings (19:00 - 22:00) or Saturdays (12:00 - 18:00).
   - Mode: Suggestion review with 1-tap confirmation.
2. **Clinical Research — Mounjaro Study (Professional):**
   - Entities: **Patient 101, Patient 102**
   - Rule: Work hours only, Mondays & Wednesdays (08:00 - 12:00), 45m duration + 15m buffer.
   - Mode: 1-year protocol roadmap (24 visits, bi-weekly cadence) with cascading rescheduling.

---

## Getting Started

### Prerequisites

- Flutter SDK (installed via `asdf` or direct binary)
- Android Studio / Xcode for device deployment

### Setup via asdf (Recommended)

```bash
asdf plugin add flutter
asdf install flutter latest
asdf global flutter latest
```

---

## Roadmap

- [x] Architectural Specification & Design System
- [ ] Phase 1: Environment & Project Bootstrap
- [ ] Phase 2: Core Domain Logic & Scheduling Engine
- [ ] Phase 3: Local Drift SQLite Storage & Seed Scenarios
- [ ] Phase 4: Device Calendar Integration
- [ ] Phase 5: Flutter 5-Tab UI (Agenda, Event Types, Entities, Scheduler, Settings)
