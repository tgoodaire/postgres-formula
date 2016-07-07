# -*- mode: yaml  -*-
# vim: syntax=yaml:sw=2

{% from "postgres/map.jinja" import postgres with context %}

{% if postgres.use_upstream_repo %}
include:
  - postgres.upstream
{% endif %}

postgresql-config-dir:
  file.directory:
    - name: {{ postgres.conf_dir }}
    - user: {{ postgres.user }}
    - group: {{ postgres.group }}
    - makedirs: True
    - require:
      - pkg: postgresql-installed
      - cmd: postgresql-cluster-prepared

postgresql-installed:
  pkg.installed:
    - name: {{ postgres.pkg }}
    - refresh: {{ postgres.use_upstream_repo }}

# make sure the data directory and contents have been initialized
postgresql-cluster-prepared:
  cmd.run:
    - cwd: /
    - name: {{ postgres.prepare_cluster.command }}
{#    #- user: {{ postgres.prepare_cluster.user }}   #}
    - user: root
    - unless:
      - {{ postgres.prepare_cluster.test }}
    - require:
      - pkg: postgresql-installed
    - env:
{% for name, value in postgres.prepare_cluster.env.items() %}
      {{ name }}: {{ value }}
{% endfor %}

postgresql-running:
  service.running:
    - enable: True
    - reload: True
    - name: {{ postgres.service }}
    - reload: true
    - require:
      - cmd: postgresql-cluster-prepared

{% if postgres.pkgs_extra %}
postgresql-extra-pkgs-installed:
  pkg.installed:
    - pkgs: {{ postgres.pkgs_extra }}
{% endif %}

{% if postgres.postgresconf %}
postgresql-conf:
  file.blockreplace:
    - name: {{ postgres.conf_dir }}/postgresql.conf
    - marker_start: "# Managed by SaltStack: listen_addresses: please do not edit"
    - marker_end: "# Managed by SaltStack: end of salt managed zone --"
    - content: |
        {{ postgres.postgresconf|indent(8) }}
    - show_changes: True
    - append_if_not_found: True
    {% if not postgres.postgresconf_backup|default(True) -%}
    - backup: False
    {% endif -%}
    - watch_in:
       - service: postgresql-running
    - require:
      - file: postgresql-config-dir
{% endif %}

postgresql-pg_hba:
  file.managed:
    - name: {{ postgres.conf_dir }}/pg_hba.conf
    - source: {{ postgres['pg_hba.conf'] }}
    - template: jinja
    - user: {{ postgres.user }}
    - group: {{ postgres.group }}
    - mode: 644
    - require:
      - file: postgresql-config-dir
    - watch_in:
      - service: postgresql-running

{% for name, user in postgres.users.items()  %}
postgresql-user-{{ name }}:
{% if user.get('ensure', 'present') == 'absent' %}
  postgres_user.absent:
    - name: {{ name }}
    - user: {{ user.get('runas', postgres.user) }}
{% else %}
  postgres_user.present:
    - name: {{ name }}
    - createdb: {{ user.get('createdb', False) }}
    - createroles: {{ user.get('createroles', False) }}
    - createuser: {{ user.get('createuser', False) }}
    - inherit: {{ user.get('inherit', True) }}
    - replication: {{ user.get('replication', False) }}
    - password: {{ user.get('password', 'changethis') }}
    - user: {{ user.get('runas', postgres.user) }}
    - superuser: {{ user.get('superuser', False) }}
{% endif %}
    - require:
      - service: postgresql-running
{% endfor %}

{% for name, directory in postgres.tablespaces.items()  %}
postgresql-tablespace-dir-perms-{{ directory}}:
  file.directory:
    - name: {{ directory }}
    - user: postgres
    - group: postgres
    - makedirs: True
    - recurse:
      - user
      - group

postgresql-tablespace-{{ name }}:
  postgres_tablespace.present:
    - name: {{ name }}
    - directory: {{ directory }}
    - user: postgres
    - require:
      - service: postgresql-running
      - file: postgresql-tablespace-dir-perms-{{ directory}}
{% endfor %}

{% for name, db in postgres.databases.items()  %}
postgresql-db-{{ name }}:
{% if db.get('ensure', 'present') == 'absent' %}
  postgres_database.absent:
    - name: {{ name }}
    - require:
      - service: postgresql-running
{% else %}
  postgres_database.present:
    - name: {{ name }}
    - encoding: {{ db.get('encoding', 'UTF8') }}
    - lc_ctype: {{ db.get('lc_ctype', 'en_US.UTF8') }}
    - lc_collate: {{ db.get('lc_collate', 'en_US.UTF8') }}
    - template: {{ db.get('template', 'template0') }}
    - tablespace: {{ db.get('tablespace', 'pg_default') }}
    {% if db.get('owner') %}
    - owner: {{ db.get('owner') }}
    {% endif %}
    - user: {{ db.get('runas', postgres.user) }}
    - require:
      - service: postgresql-running
    {% if db.get('tablespace') %}
      - postgres_tablespace: postgresql-tablespace-{{ name }}
    {% endif %}
    {% if db.get('owner') %}
      - postgres_user: postgresql-user-{{ db.get('owner') }}
   {% endif %}

{% if db.schemas is defined %}
{% for schema, schema_args in db.schemas.items() %}
postgresql-schema-{{ schema }}-for-db-{{ name }}:
  postgres_schema.present:
    - name: {{ schema }}
    - dbname: {{ name }}
{% if schema_args is not none %}
{% for arg, value in schema_args.items() %}
    - {{ arg }}: {{ value }}
{% endfor %}
    - require:
      - service: postgresql-running
{% endif %}
{% endfor %}
{% endif %}

{% if db.extensions is defined %}
{% for ext, ext_args in db.extensions.items() %}
postgresql-ext-{{ ext }}-for-db-{{ name }}:
  postgres_extension.present:
    - name: {{ ext }}
    - user: {{ db.get('runas', postgres.user) }}
    - maintenance_db: {{ name }}
{% if ext_args is not none %}
{% for arg, value in ext_args.items() %}
    - {{ arg }}: {{ value }}
{% endfor %}
    - require:
      - service: postgresql-running
{% endif %}
{% endfor %}
{% endif %}
{% endif %}
{% endfor %}

