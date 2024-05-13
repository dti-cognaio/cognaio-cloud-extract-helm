--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4 (Debian 15.4-2.pgdg120+1)
-- Dumped by pg_dump version 15.2

-- Started on 2024-01-25 18:15:42

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 9 (class 2615 OID 16384)
-- Name: cognaio_extensions; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cognaio_extensions;


ALTER SCHEMA cognaio_extensions OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA cognaio_extensions;
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA cognaio_extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA cognaio_extensions;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 253 (class 1259 OID 24757)
-- Name: schema_versions; Type: TABLE; Schema: cognaio_extensions; Owner: postgres
--

CREATE TABLE cognaio_extensions.schema_versions (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    version text NOT NULL,
    description text,
    appliedat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_extensions.schema_versions OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 3545 (class 2606 OID 24765)
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: cognaio_extensions; Owner: postgres
--

ALTER TABLE ONLY cognaio_extensions.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (key);


--
-- TOC entry 3543 (class 1259 OID 24766)
-- Name: schema_version_number; Type: INDEX; Schema: cognaio_extensions; Owner: postgres
--

CREATE UNIQUE INDEX schema_version_number ON cognaio_extensions.schema_versions USING btree (lower(version));


INSERT INTO cognaio_extensions.schema_versions (version, description) VALUES ('2.2.0.0', 'cognaio version 2.2');


-- Completed on 2024-01-25 18:15:43

--
-- PostgreSQL database dump complete
--

