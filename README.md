# Vortexify Partner Control Center

This repository contains the internal Vortexify Partner Org application.

## Purpose

This app manages:

- Subscriber org records
- Subscription plans
- Feature entitlements
- Provider license allocation
- Provider number allocation
- Usage records
- Usage summaries
- Invoice staging
- Partner support/admin dashboards

## Important

This repo is not the customer managed package.

Customer managed package source lives separately in:

vortexify-cti-managed-package

This Partner Control Center app is deployed only to Vortexify Partner Org environments.

## Common Commands

Login to Partner Org:

sf org login web --alias vtx-partner-dev

Deploy:

./scripts/deploy-partner-org.sh vtx-partner-dev

Retrieve:

./scripts/retrieve-partner-org.sh vtx-partner-dev
