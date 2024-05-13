--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4 (Debian 15.4-2.pgdg120+1)
-- Dumped by pg_dump version 15.2

-- Started on 2024-04-22 15:41:33

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
-- TOC entry 11 (class 2615 OID 17292)
-- Name: cognaio_repositories; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cognaio_repositories;


ALTER SCHEMA cognaio_repositories OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 427 (class 1255 OID 17293)
-- Name: create_repository(json, text); Type: PROCEDURE; Schema: cognaio_repositories; Owner: postgres
--

CREATE PROCEDURE cognaio_repositories.create_repository(IN repository_in json, IN encryptionkey text, OUT repository_key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	repoContent text;
	index_data json;
	expires_in_days integer;
BEGIN
    timestamp_current = timezone('UTC', now());
	expires_in_days = (repository_in->>'repoExpiresInDays')::integer;
	DELETE FROM cognaio_repositories.repository_index WHERE fk_repo = (repository_in->>'key')::uuid;
	DELETE FROM cognaio_repositories.repository WHERE key = (repository_in->>'key')::uuid;
		
	INSERT INTO cognaio_repositories.repository (
		key, organization, businessunit, repo_kind, context, options, repo_content, expiresat
	)
	VALUES(
		(repository_in->>'key')::uuid
		, (repository_in->>'organization')::uuid
		, (repository_in->>'businessunit')::uuid
		, (repository_in->>'repoKind')::text
		, (repository_in->>'repoContext')::text
		, (repository_in->>'options')::json
		, cognaio_extensions.pgp_sym_encrypt(repository_in->>'repoContent', encryptionKey, 'compress-algo=1, cipher-algo=aes256')
		, Case WHEN expires_in_days is not null then timestamp_current + MAKE_INTERVAL(days => expires_in_days) else null END
	) RETURNING key INTO repository_key_out;
	
	FOR index_data IN SELECT * FROM json_array_elements((repository_in->>'index')::json)
   	LOOP
		INSERT INTO cognaio_repositories.repository_index (
			fk_repo, context, index_content
		)
		VALUES(
			repository_key_out
			, (index_data->>'key')::text
			, cognaio_extensions.pgp_sym_encrypt(index_data->>'data', encryptionKey, 'compress-algo=1, cipher-algo=aes256')
		);
	END LOOP;
	
END
$$;


ALTER PROCEDURE cognaio_repositories.create_repository(IN repository_in json, IN encryptionkey text, OUT repository_key_out uuid) OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 415 (class 1255 OID 17294)
-- Name: get_repository(uuid, json, text); Type: PROCEDURE; Schema: cognaio_repositories; Owner: postgres
--

CREATE PROCEDURE cognaio_repositories.get_repository(IN repository_key_in uuid, IN options_in json, IN encryptionkey text, OUT repo_out json)
    LANGUAGE plpgsql
    AS $$
DECLARE
	repocontent text;
	repocontent_arr json;
BEGIN
	WITH sq AS
		(
			SELECT a.repo_kind
				, b.context as index_context
				, cognaio_extensions.pgp_sym_decrypt(b.index_content, encryptionKey, 'compress-algo=1, cipher-algo=aes256') as index_content
				, a.options
			FROM cognaio_repositories.repository a
			INNER JOIN cognaio_repositories.repository_index b ON a.key = b.fk_repo
			AND a.key = repository_key_in
	)
	SELECT json_agg(row_to_json(sq)) FROM sq INTO repo_out;
	
	if options_in is not null and (options_in->>'includeRepoContent')::boolean is TRUE THEN
		WITH sqs AS
		(
			SELECT cognaio_extensions.pgp_sym_decrypt(repo_content, encryptionKey, 'compress-algo=1, cipher-algo=aes256') as repo_content FROM cognaio_repositories.repository WHERE key = repository_key_in
		)
		SELECT json_agg(row_to_json(sqs)) FROM sqs INTO repocontent_arr;
		
		repo_out = format('{
			"content": %s,
			"indexes": %s
		}', repocontent_arr, repo_out);
	else
		repo_out = format('{
			"indexes": %s
		}', repo_out);
	end if;
	
END
$$;


ALTER PROCEDURE cognaio_repositories.get_repository(IN repository_key_in uuid, IN options_in json, IN encryptionkey text, OUT repo_out json) OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 232 (class 1259 OID 17295)
-- Name: repository; Type: TABLE; Schema: cognaio_repositories; Owner: postgres
--

CREATE TABLE cognaio_repositories.repository (
    key uuid NOT NULL,
    organization uuid NOT NULL,
    businessunit text,
    repo_kind text DEFAULT 'fullText'::text NOT NULL,
    context text NOT NULL,
    options json,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    repo_content bytea,
    expiresat timestamp without time zone
);


ALTER TABLE cognaio_repositories.repository OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 249 (class 1259 OID 75130)
-- Name: repository_embeddings; Type: TABLE; Schema: cognaio_repositories; Owner: postgres
--

CREATE TABLE cognaio_repositories.repository_embeddings (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_repo uuid NOT NULL,
    content text,
    embedding cognaio_extensions.vector,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    expiresat timestamp without time zone
);


ALTER TABLE cognaio_repositories.repository_embeddings OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 233 (class 1259 OID 17302)
-- Name: repository_index; Type: TABLE; Schema: cognaio_repositories; Owner: postgres
--

CREATE TABLE cognaio_repositories.repository_index (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_repo uuid NOT NULL,
    context text NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    index_content bytea
);


ALTER TABLE cognaio_repositories.repository_index OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 234 (class 1259 OID 17309)
-- Name: schema_versions; Type: TABLE; Schema: cognaio_repositories; Owner: postgres
--

CREATE TABLE cognaio_repositories.schema_versions (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    version text NOT NULL,
    description text,
    appliedat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_repositories.schema_versions OWNER TO {{ .Values.cognaioflexsearchservice.env.db.postgreSqlUser }};

--
-- TOC entry 3615 (class 2606 OID 75138)
-- Name: repository_embeddings embeddings_pkey; Type: CONSTRAINT; Schema: cognaio_repositories; Owner: postgres
--

ALTER TABLE ONLY cognaio_repositories.repository_embeddings
    ADD CONSTRAINT embeddings_pkey PRIMARY KEY (key);


--
-- TOC entry 3610 (class 2606 OID 17317)
-- Name: repository_index repository_index_pkey; Type: CONSTRAINT; Schema: cognaio_repositories; Owner: postgres
--

ALTER TABLE ONLY cognaio_repositories.repository_index
    ADD CONSTRAINT repository_index_pkey PRIMARY KEY (key);


--
-- TOC entry 3608 (class 2606 OID 17319)
-- Name: repository repository_pkey; Type: CONSTRAINT; Schema: cognaio_repositories; Owner: postgres
--

ALTER TABLE ONLY cognaio_repositories.repository
    ADD CONSTRAINT repository_pkey PRIMARY KEY (key);


--
-- TOC entry 3613 (class 2606 OID 17321)
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: cognaio_repositories; Owner: postgres
--

ALTER TABLE ONLY cognaio_repositories.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (key);


--
-- TOC entry 3611 (class 1259 OID 17322)
-- Name: schema_version_number; Type: INDEX; Schema: cognaio_repositories; Owner: postgres
--

CREATE UNIQUE INDEX schema_version_number ON cognaio_repositories.schema_versions USING btree (lower(version));

INSERT INTO cognaio_repositories.schema_versions (version, description) VALUES ('2.2.0.0', 'cognaio version 2.2');

--
-- TOC entry 3616 (class 2606 OID 75139)
-- Name: repository_embeddings fk_repo; Type: FK CONSTRAINT; Schema: cognaio_repositories; Owner: postgres
--

ALTER TABLE ONLY cognaio_repositories.repository_embeddings
    ADD CONSTRAINT fk_repo FOREIGN KEY (fk_repo) REFERENCES cognaio_repositories.repository(key) ON DELETE CASCADE;


-- Completed on 2024-04-22 15:41:35

--
-- PostgreSQL database dump complete
--
