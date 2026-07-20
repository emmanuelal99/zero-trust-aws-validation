# Wazuh SIEM

Detection/monitoring layer for both environments. Wazuh agents run on the EC2 hosts and
ship events to the Wazuh manager; custom rules/decoders raise alerts used to compute MTTD
and CDI.

- `docker-compose.yml` — Wazuh single-node stack (manager, indexer, dashboard) for the
  analysis host *(TODO)*
- `rules/`    — custom detection rules for Logi-Track / attack techniques
- `decoders/` — custom log decoders

The `wazuh` Terraform module provisions the manager host; agents are installed via EC2
user-data in the `compute` module.
