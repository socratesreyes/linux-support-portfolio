# MySQL Support Queries — Evidence
This folder contains the support-triage SQL queries used in my lab (`mysql-support-queries.sql`).

Below is the visual evidence of the queries running against the lab database.

>  Lab Infrastructure & Environment

This project was fully engineered and deployed within a **self-managed Ubuntu Server lab environment** utilizing **Docker containers** for microservices isolation.

- **Host OS:** Ubuntu Server (`root@ubuntuserver`)
- **Container Engine:** Docker Engine - Community (v29.9)
- **Database Engine:** MySQL 8.0 Community Server (Running via Docker container: `sql-lab-mysql-1`)
- **Data Privacy:** All hostnames, user credentials, and PII are strictly **synthetic/mock data** to mirror enterprise data-sanitization standards.

Dataset Scale & Stress Testing

The database schema populates standard operational tables (`clients`=5, `users`=8, `cases`=8) alongside a **~500,000-row bulk transfer table (`transfers_bulk`)** explicitly generated to test query optimization, indexing, and container resource limits under heavy loads.

## 0. Sanity Checks

**0.1 Confirm you're on the right server and database**
![](linux-support-portfolio/08-evidence/screenshots/Screenshot_2026-10-27_19-07-02%201.png)



**0.2 Row counts**

![](linux-support-portfolio/08-evidence/screenshots/Screenshot_2026-10-28_09-52-24.png)


![](../08-evidence/screenshots/Screenshot_2026-10-27_19-07-02%203.png)