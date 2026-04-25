# syntax=docker/dockerfile:1
# Builds ERPNext v15 + HRMS + hr_client into one image
FROM frappe/erpnext:v15 AS base

USER root
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe/frappe-bench

ARG HRMS_BRANCH=version-15
ARG HR_CLIENT_BRANCH=develop
ARG HR_CLIENT_REPO=https://github.com/KernelLex/hr-client-erp.git

# Install hrms
RUN git clone --depth 1 --branch ${HRMS_BRANCH} \
        https://github.com/frappe/hrms.git apps/hrms \
    && /home/frappe/frappe-bench/env/bin/pip install \
        --no-cache-dir -q -e apps/hrms

# Install hr_client
RUN git clone --depth 1 --branch ${HR_CLIENT_BRANCH} \
        ${HR_CLIENT_REPO} apps/hr_client \
    && /home/frappe/frappe-bench/env/bin/pip install \
        --no-cache-dir -q -e apps/hr_client
