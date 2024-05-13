--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4 (Debian 15.4-2.pgdg120+1)
-- Dumped by pg_dump version 15.2

-- Started on 2024-04-09 17:25:01

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
-- TOC entry 12 (class 2615 OID 28167)
-- Name: cognaio_audits; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cognaio_audits;


ALTER SCHEMA cognaio_audits OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 1133 (class 1247 OID 30822)
-- Name: audit_status; Type: TYPE; Schema: cognaio_audits; Owner: postgres
--

CREATE TYPE cognaio_audits.audit_status AS ENUM (
    'await_processing',
    'processing',
    'processing_done',
    'processing_error'
);


ALTER TYPE cognaio_audits.audit_status OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 1103 (class 1247 OID 28169)
-- Name: envelope_artifact_status; Type: TYPE; Schema: cognaio_audits; Owner: postgres
--

CREATE TYPE cognaio_audits.envelope_artifact_status AS ENUM (
    'created',
    'processing_requested',
    'processing',
    'processing_done',
    'processing_error'
);


ALTER TYPE cognaio_audits.envelope_artifact_status OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 250 (class 1259 OID 28179)
-- Name: appkey_audit_artifacts_static_image; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audit_artifacts_static_image (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_audit uuid NOT NULL,
    original_audit_ref uuid,
    image_name text,
    image_content_type text,
    starts_at_index_in_main integer,
    image_binaries bytea,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    image_index_in_chain integer,
    image_pages_count integer
);


ALTER TABLE cognaio_audits.appkey_audit_artifacts_static_image OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 421 (class 1255 OID 30832)
-- Name: auditartifacts_static_images(uuid, boolean, text); Type: FUNCTION; Schema: cognaio_audits; Owner: postgres
--

CREATE FUNCTION cognaio_audits.auditartifacts_static_images(auditkey uuid, skip_download_binaries boolean, encryptionkey text) RETURNS SETOF cognaio_audits.appkey_audit_artifacts_static_image
    LANGUAGE plpgsql
    AS $$
          DECLARE 
            r record;
            fk_audit_from_original_audit_ref uuid;
            images_to_consider uuid[];
          BEGIN
          SELECT original_audit_ref into fk_audit_from_original_audit_ref from cognaio_audits.appkey_audit_artifacts_static_image WHERE fk_audit = auditkey;
            IF fk_audit_from_original_audit_ref is NOT NULL THEN
            auditkey = fk_audit_from_original_audit_ref;
            END IF;
            images_to_consider := ARRAY(SELECT key from cognaio_audits.appkey_audit_artifacts_static_image WHERE fk_audit = auditkey);
            FOR r IN SELECT 
              key
              , fk_audit
              , original_audit_ref
              , image_name
              , image_content_type
              , starts_at_index_in_main
              , CASE WHEN skip_download_binaries IS FALSE THEN cognaio_extensions.pgp_sym_decrypt_bytea(image_binaries, encryptionKey, 'compress-algo=1, cipher-algo=aes256') ELSE NULL END
              , createdat
              , modifiedat
              , image_index_in_chain
              , image_pages_count
              FROM cognaio_audits.appkey_audit_artifacts_static_image 
              WHERE key = ANY(images_to_consider)
            LOOP
              RETURN NEXT r;
            END LOOP;
          END;
      
    $$;


ALTER FUNCTION cognaio_audits.auditartifacts_static_images(auditkey uuid, skip_download_binaries boolean, encryptionkey text) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 410 (class 1255 OID 28187)
-- Name: create_appkey_report(uuid, boolean, json, timestamp without time zone, text, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.create_appkey_report(IN appkey uuid, IN auditsenabled boolean, IN externals_in json, IN timstamptoconsider timestamp without time zone, IN timestamprange text, IN language text, OUT auditjson json)
    LANGUAGE plpgsql
    AS $$
    DECLARE
        key_createdat text;
        key_expiresat text;
        timstamp_current timestamp;
        timstamp_min timestamp;
        timstamp_max timestamp;
      given_app_scope_key uuid; 
      given_app_plan_key uuid;  
      given_user_key uuid; 
      currentitems integer;
        itemsleft integer;
        itemsallowed integer;
        limitationtype text;
        limitationscope text;
      appKeyOwner text;
      scope_name text;
      scope_desc text;
      plan_name text;
      plan_type text;
      plan_desc text;
      docsdelivered integer;
      pagesdelivered integer;
      avgpagesdeliveredinsec numeric;
      minpagesperdocument integer;
      maxpagesperdocument integer;
    BEGIN
      
      given_app_plan_key = (externals_in->>'plan_key')::uuid;
      plan_name = externals_in->>'plan_name';
      plan_desc = externals_in->>'plan_desc';
      plan_type = externals_in->>'plan_type'; 
      given_user_key = (externals_in->>'user_key')::uuid;
      appKeyOwner = externals_in->>'appKeyOwner'; 
      key_createdat = externals_in->>'appKey_createdat';
      key_expiresat = externals_in->>'appKey_expiresat';
      given_app_scope_key = (externals_in->>'scope_key')::uuid;
      scope_name = externals_in->>'scope_name';
      scope_desc = externals_in->>'scope_desc';
      itemsallowed = externals_in->>'itemsallowed';
      limitationtype = externals_in->>'limitationtype';
      limitationscope = externals_in->>'limitationscope';
        
        timstamp_current = timezone('UTC', now());
        if(limitationscope = 'minute') then
            timstamp_min = date_trunc('minute', timstamp_current);
            timstamp_max = date_trunc('minute', timstamp_current + interval '1 minute');
        elsif (limitationscope = 'hour') then
            timstamp_min = date_trunc('hour', timstamp_current);
            timstamp_max = date_trunc('hour', timstamp_current + interval '1 hour');
        elsif (limitationscope = 'day') then
            timstamp_min = date_trunc('day', timstamp_current);
            timstamp_max = date_trunc('day', timstamp_current + interval '1 day');
        elsif (limitationscope = 'week') then
            timstamp_min = date_trunc('week', timstamp_current);
            timstamp_max = date_trunc('week', timstamp_current + interval '1 week');
        elsif (limitationscope = 'month') then
            timstamp_min = date_trunc('month', timstamp_current);
            timstamp_max = date_trunc('month', timstamp_current + interval '1 month');
        else
            timstamp_min = date_trunc('year', timstamp_current);
            timstamp_max = date_trunc('year', timstamp_current + interval '1 year');
        end if;
        
        RAISE NOTICE 'createauditreport() timstamp_min: %', timstamp_min;
        RAISE NOTICE 'createauditreport() timstamp_max: %', timstamp_max;    
        
      if limitationtype = 'page' then
        SELECT sum(documentpagesarrived) INTO currentitems
          FROM cognaio_audits.appkey_audits_history  
                WHERE fk_plan = given_app_plan_key
          AND date between timstamp_min and timstamp_max;
      else
        SELECT sum(documentsarrived) INTO currentitems
          FROM cognaio_audits.appkey_audits_history 
                WHERE fk_plan = given_app_plan_key
          AND date between timstamp_min and timstamp_max;
      end if;
            
        if currentitems is null then
            currentitems = 0;
        end if;

        RAISE NOTICE 'createauditreport() timestamprange: %', timestamprange;
        RAISE NOTICE 'createauditreport() itemsallowed: %', itemsallowed;
        RAISE NOTICE 'createauditreport() limitationtype: %', limitationtype;
        RAISE NOTICE 'createauditreport() limitationscope: %', limitationscope;
        RAISE NOTICE 'createauditreport() currentitems: %', currentitems;

        itemsleft = itemsallowed - currentitems;
        
        if auditsenabled = true then    
            if (timestamprange = 'hour') then
                timstamp_min = date_trunc('hour', timstamptoconsider);
                timstamp_max = date_trunc('hour', timstamptoconsider + interval '1 hour');
            elsif (timestamprange = 'day') then
                timstamp_min = date_trunc('day', timstamptoconsider);
                timstamp_max = date_trunc('day', timstamptoconsider + interval '1 day');
            elsif (timestamprange = 'week') then
                timstamp_min = date_trunc('week', timstamptoconsider);
                timstamp_max = date_trunc('week', timstamptoconsider + interval '1 week');
            elsif (timestamprange = 'month') then
                timstamp_min = date_trunc('month', timstamptoconsider);
                timstamp_max = date_trunc('month', timstamptoconsider + interval '1 month');
            else
                timstamp_min = date_trunc('year', timstamptoconsider);
                timstamp_max = date_trunc('year', timstamptoconsider + interval '1 year');
            end if;
            
            RAISE NOTICE 'createauditreport() timstamp_min: %', timstamp_min;
            RAISE NOTICE 'createauditreport() timstamp_max: %', timstamp_max; 

            SELECT sum(documentsdelivered), sum(documentpagesdelivered), ROUND(AVG(processing_duration_msec/documentpagesdelivered::numeric/1000), 2), 
          		0, 0 INTO docsdelivered, pagesdelivered, avgpagesdeliveredinsec, maxpagesperdocument, minpagesperdocument
            FROM cognaio_audits.appkey_audits_history
            WHERE fk_plan = given_app_plan_key
            AND documentpagesdelivered IS NOT NULL 
            AND documentpagesdelivered > 0
            AND date between timstamp_min and timstamp_max;

            if pagesdelivered is null then
                docsdelivered = 0;
                pagesdelivered = 0;
                avgpagesdeliveredinsec = 0;
                maxpagesperdocument = 0;
                minpagesperdocument = 0;
            end if;

            auditjson = format('{
                "key": {
              "owner": "%s",
                    "createdAt": "%s",
                    "expiresAt": "%s"
                },
                "scope": {
                    "name": "%s",
                    "description": "%s"
                },
                "plan": {
                    "name": "%s",
                    "description": "%s",
                    "type": "%s",
                    "maxitemsLimit": %s,
                    "itemsLeft": %s,
                    "limitationType": "%s",
                    "limitationScope": "%s"
                },
                "audit": {
                    "range": "%s",
                    "start": "%s",
                    "end": "%s",
                    "documentsdelivered": %s,
                    "pagesdelivered": %s,
                    "avgpagesdeliveredinsec": %s,
                    "maxpagesperdocument": %s,
                    "minpagesperdocument": %s
                }
            }', appKeyOwner, key_createdat, key_expiresat, scope_name, scope_desc, plan_name, plan_desc, plan_type, itemsallowed, itemsleft, limitationtype, limitationscope, timestamprange, timstamp_min, timstamp_max, docsdelivered, pagesdelivered, avgpagesdeliveredinsec, maxpagesperdocument, minpagesperdocument);
      else        
            auditjson = format('{
                "key": {
              "owner": "%s",
                    "createdAt": "%s",
                    "expiresAt": "%s"
                },
                "scope": {
                    "name": "%s",
                    "description": "%s"
                },
                "plan": {
                    "name": "%s",
                    "description": "%s",
                    "type": "%s",
                    "maxitemsLimit": %s,
                    "itemsLeft": %s,
                    "limitationType": "%s",
                    "limitationScope": "%s"
                }
            }', appKeyOwner, key_createdat, key_expiresat, scope_name, scope_desc, plan_name, plan_desc, plan_type, itemsallowed, itemsleft, limitationtype, limitationscope);
      end if;
        
        RAISE NOTICE 'createauditreport() auditjson: %', auditjson;
        RAISE NOTICE 'createauditreport() Transaction ID: %', TXID_CURRENT();
      
    END
    
$$;


ALTER PROCEDURE cognaio_audits.create_appkey_report(IN appkey uuid, IN auditsenabled boolean, IN externals_in json, IN timstamptoconsider timestamp without time zone, IN timestamprange text, IN language text, OUT auditjson json) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 406 (class 1255 OID 28189)
-- Name: create_envelope(json, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.create_envelope(IN envelope_in json, IN encryptionkey text, OUT envelope_key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
BEGIN
    timestamp_current = timezone('UTC', now());
	
	INSERT INTO cognaio_audits.envelope_audits (
		key, fk_mailbox_key, fk_app_key, fk_user, fk_plan, fk_envelope, envelope_id, envelope_subject, envelope_from, envelope_to, envelope_cc, envelope_bcc, metadata
	)
			VALUES(
				(envelope_in->>'key')::uuid
				, (envelope_in->>'fk_mailbox_key')::uuid
				, (envelope_in->>'fk_app_key')::uuid
				, (envelope_in->>'fk_user')::uuid
				, (envelope_in->>'fk_plan')::uuid
				, (envelope_in->>'fk_envelope')::uuid
				, (envelope_in->>'envelope_id')::text
				, (envelope_in->>'envelope_subject')::text
				, (envelope_in->>'envelope_from')::text
				, (envelope_in->>'envelope_to')::text
				, (envelope_in->>'envelope_cc')::text
				, (envelope_in->>'envelope_bcc')::text
				, encode(cognaio_extensions.pgp_sym_encrypt((envelope_in->>'metadata'::text), encryptionKey, 'compress-algo=1, cipher-algo=aes256'), 'base64')
			) RETURNING key INTO envelope_key_out;
END
$$;


ALTER PROCEDURE cognaio_audits.create_envelope(IN envelope_in json, IN encryptionkey text, OUT envelope_key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 407 (class 1255 OID 28190)
-- Name: create_envelope_artifact(uuid, uuid, text, text, bytea, text, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.create_envelope_artifact(IN envelopekey uuid, IN auditkey uuid, IN artifactname text, IN artifactcontenttype text, IN artifactbinaries bytea, IN artifactstatus text, IN encryptionkey text, OUT artifact_key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
BEGIN
    timestamp_current = timezone('UTC', now());
	
	INSERT INTO cognaio_audits.envelope_artifact_audits (fk_envelope, audit_key, artifact_name, artifact_content_type, status, artifact_binaries)
			VALUES(
				envelopekey
				, auditkey
				, artifactname
				, artifactcontenttype
				, artifactstatus::envelope_artifact_status
				, cognaio_extensions.pgp_sym_encrypt_bytea(artifactbinaries, encryptionKey, 'compress-algo=1, cipher-algo=aes256')
			) RETURNING key INTO artifact_key_out;
END
$$;


ALTER PROCEDURE cognaio_audits.create_envelope_artifact(IN envelopekey uuid, IN auditkey uuid, IN artifactname text, IN artifactcontenttype text, IN artifactbinaries bytea, IN artifactstatus text, IN encryptionkey text, OUT artifact_key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 408 (class 1255 OID 28191)
-- Name: createorupdate_auditartifacts_extraction(uuid, json, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.createorupdate_auditartifacts_extraction(IN auditkey uuid, IN artifacts_in json, IN encryptionkey text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	artifacts_fields_results text;
	artifacts_ai_entities_results text;
	artifacts_ai_entities_prompt text;
	artifacts_ai_feedback_results text;
BEGIN
    timestamp_current = timezone('UTC', now());
	
	artifacts_fields_results = artifacts_in->'fields_results';
	artifacts_ai_entities_results = artifacts_in->'ai_entities_results';
	artifacts_ai_entities_prompt = artifacts_in->'ai_entities_prompt';
	artifacts_ai_feedback_results = artifacts_in->'feedback_results';
	
	if artifacts_fields_results is not null then
		INSERT INTO cognaio_audits.appkey_audit_artifacts_extraction (fk_audit, fields_results, createdat)
			VALUES(auditkey, cognaio_extensions.pgp_sym_encrypt(artifacts_fields_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') , timestamp_current) 
		ON CONFLICT (fk_audit)
		DO 
		   UPDATE SET 
		   	fields_results = cognaio_extensions.pgp_sym_encrypt(artifacts_fields_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256'),
			modifiedat = timestamp_current;
	end if;
	
	if artifacts_ai_entities_results is not null then
		INSERT INTO cognaio_audits.appkey_audit_artifacts_extraction (fk_audit, ai_entities_results, createdat)
			VALUES(auditkey, cognaio_extensions.pgp_sym_encrypt(artifacts_ai_entities_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') , timestamp_current) 
		ON CONFLICT (fk_audit)
		DO 
		   UPDATE SET 
		   	ai_entities_results = cognaio_extensions.pgp_sym_encrypt(artifacts_ai_entities_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256'),
			modifiedat = timestamp_current;
	end if;
	
	if artifacts_ai_entities_prompt is not null then
		INSERT INTO cognaio_audits.appkey_audit_artifacts_extraction (fk_audit, ai_entities_prompt, createdat)
			VALUES(auditkey, cognaio_extensions.pgp_sym_encrypt(artifacts_ai_entities_prompt, encryptionKey, 'compress-algo=1, cipher-algo=aes256') , timestamp_current) 
		ON CONFLICT (fk_audit)
		DO 
		   UPDATE SET 
		   	ai_entities_prompt = cognaio_extensions.pgp_sym_encrypt(artifacts_ai_entities_prompt, encryptionKey, 'compress-algo=1, cipher-algo=aes256'),
			modifiedat = timestamp_current;
	end if;
	
	if artifacts_ai_feedback_results is not null then
		INSERT INTO cognaio_audits.appkey_audit_artifacts_extraction (fk_audit, feedback_results, createdat)
			VALUES(auditkey, cognaio_extensions.pgp_sym_encrypt(artifacts_ai_feedback_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') , timestamp_current) 
		ON CONFLICT (fk_audit)
		DO 
		   UPDATE SET 
		   	feedback_results = cognaio_extensions.pgp_sym_encrypt(artifacts_ai_feedback_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256'),
			modifiedat = timestamp_current;
	end if;	
END
$$;


ALTER PROCEDURE cognaio_audits.createorupdate_auditartifacts_extraction(IN auditkey uuid, IN artifacts_in json, IN encryptionkey text) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 423 (class 1255 OID 30834)
-- Name: createorupdate_auditartifacts_static(uuid, uuid, text, text, integer, integer, integer, bytea, json, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.createorupdate_auditartifacts_static(IN auditkey uuid, IN imagekey uuid, IN imagename text, IN imagecontenttype text, IN startsatindexinmain integer, IN image_index_in_chain integer, IN image_pages integer, IN imagebinaries bytea, IN artifacts_in json, IN encryptionkey text)
    LANGUAGE plpgsql
    AS $$
      DECLARE
        timestamp_current timestamp;
        artifacts_ocr_results text;
      BEGIN
        timestamp_current = timezone('UTC', now());      
        artifacts_ocr_results = artifacts_in->'ocr_results';
        
        if imagekey is not null then
          INSERT INTO cognaio_audits.appkey_audit_artifacts_static_image (key
                                      , fk_audit
                                      , image_name
                                      , image_content_type
                                      , starts_at_index_in_main
                                      , image_binaries
                                      , createdat
                                      , image_index_in_chain
                                      , image_pages_count)
            VALUES(imagekey
          , auditkey
          , imagename
          , imagecontenttype
          , startsatindexinmain
          , cognaio_extensions.pgp_sym_encrypt_bytea(imagebinaries, encryptionKey, 'compress-algo=1, cipher-algo=aes256')
          , timestamp_current
          , image_index_in_chain
          , image_pages);
        end if;
        
        if artifacts_ocr_results is not null then
          INSERT INTO cognaio_audits.appkey_audit_artifacts_static_ocr (fk_audit, ocr_results, createdat)
            VALUES(auditkey, cognaio_extensions.pgp_sym_encrypt(artifacts_ocr_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') , timestamp_current) 
          ON CONFLICT (fk_audit)
          DO 
            UPDATE SET 
              ocr_results = cognaio_extensions.pgp_sym_encrypt(artifacts_ocr_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256'),
              modifiedat = timestamp_current;
        end if;	
      END
        
    $$;


ALTER PROCEDURE cognaio_audits.createorupdate_auditartifacts_static(IN auditkey uuid, IN imagekey uuid, IN imagename text, IN imagecontenttype text, IN startsatindexinmain integer, IN image_index_in_chain integer, IN image_pages integer, IN imagebinaries bytea, IN artifacts_in json, IN encryptionkey text) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 422 (class 1255 OID 30833)
-- Name: get_audit_information(uuid, uuid); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.get_audit_information(IN audit_key uuid, IN plan_key uuid, OUT auditjson json)
    LANGUAGE plpgsql
    AS $$
        DECLARE
        timestamp_current timestamp;
        timestamp_min timestamp;
        timestamp_max timestamp;
        itemsleft integer;
        currentitems integer;
        json_audit json;
        json_plan json;
        json_project json;
        BEGIN
        timestamp_current = timezone('UTC', now());
        
        SELECT row_to_json(audit) FROM (SELECT documentname, fk_plan, fk_project, status, measurements, errors, deliveredat FROM cognaio_audits.appkey_audits WHERE key = audit_key and fk_plan = plan_key) as audit INTO json_audit;
        RAISE NOTICE 'get_audit_information(0) json_audit: %', json_audit;
        if json_audit->>'fk_plan' is NULL then 
          RAISE EXCEPTION 'unable to find audit with given key'
                USING HINT = 'Please check your audit token';
        end if;
        
        SELECT row_to_json(plan) FROM (SELECT name, description, maxitems, maxitems_type, maxitems_scope FROM cognaio_design.app_plans WHERE key = (json_audit->>'fk_plan')::uuid) as plan INTO json_plan;
        RAISE NOTICE 'get_audit_information(0) json_plan: %', json_plan;
        SELECT row_to_json(project) FROM (SELECT name FROM cognaio_design.def_process_projects WHERE key = (json_audit->>'fk_project')::uuid) as project INTO json_project;
        RAISE NOTICE 'get_audit_information(0) json_project: %', json_project;
            
        if(json_plan->>'maxitems_scope' = 'minute') then
          timestamp_min = date_trunc('minute', timestamp_current);
          timestamp_max = date_trunc('minute', timestamp_current + interval '1 minute');
        elsif (json_plan->>'maxitems_scope' = 'hour') then
          timestamp_min = date_trunc('hour', timestamp_current);
          timestamp_max = date_trunc('hour', timestamp_current + interval '1 hour');
        elsif (json_plan->>'maxitems_scope' = 'day') then
          timestamp_min = date_trunc('day', timestamp_current);
          timestamp_max = date_trunc('day', timestamp_current + interval '1 day');
        elsif (json_plan->>'maxitems_scope' = 'week') then
          timestamp_min = date_trunc('week', timestamp_current);
          timestamp_max = date_trunc('week', timestamp_current + interval '1 week');
        elsif (json_plan->>'maxitems_scope' = 'month') then
          timestamp_min = date_trunc('month', timestamp_current);
          timestamp_max = date_trunc('month', timestamp_current + interval '1 month');
        elsif (json_plan->>'maxitems_scope' = 'quarter') then
          timestamp_min = date_trunc('quarter', timestamp_current);
          timestamp_max = date_trunc('quarter', timestamp_current + interval '1 quarter');
        else
          timestamp_min = date_trunc('year', timestamp_current);
          timestamp_max = date_trunc('year', timestamp_current + interval '1 year');
        end if;

        RAISE NOTICE 'get_audit_information() timestamp_min: %', timestamp_min;
        RAISE NOTICE 'get_audit_information() timestamp_max: %', timestamp_max;

        if json_plan->>'maxitems_type' = 'page' then
          if json_plan->>'maxitems_scope' = 'hour' or json_plan->>'maxitems_scope' = 'minute' then
            SELECT sum(documentpagesarrived) INTO currentitems
            FROM cognaio_audits.appkey_audits  
            WHERE fk_plan = plan_key
            AND arrivedat between timestamp_min and timestamp_max;
            else
            SELECT sum(documentpagesarrived) INTO currentitems
            FROM cognaio_audits.appkey_audits_history 
            WHERE fk_plan = plan_key
            AND date between timestamp_min and timestamp_max;
            
            RAISE NOTICE 'get_audit_information() currentitems (%, page) from appkey_audits_history: %', json_plan->>'maxitems_type', currentitems;
          end if;
        else
          if json_plan->>'maxitems_scope' = 'hour' or json_plan->>'maxitems_scope' = 'minute' then
            SELECT sum(documentsarrived) INTO currentitems
            FROM cognaio_audits.appkey_audits   
            WHERE fk_plan = (json_audit->>'fk_plan')::uuid
            AND arrivedat between timestamp_min and timestamp_max;
            else
            SELECT sum(documentsarrived) INTO currentitems
            FROM cognaio_audits.appkey_audits_history 
            WHERE fk_plan = (json_audit->>'fk_plan')::uuid
            AND date between timestamp_min and timestamp_max;
            
            RAISE NOTICE 'get_audit_information() currentitems (%, document) from appkey_audits_history: %', json_plan->>'maxitems_type', currentitems;
          end if;
        end if;
          
        if currentitems is null then
          currentitems = 0;
        end if;
        
        itemsleft = (json_plan->>'maxitems')::integer - currentitems;
        
        SELECT json_build_object(
          'audit', json_build_object(
            'key', audit_key,
            'name', json_audit->>'documentname',
            'timestamp', timestamp_current,
            'itemsLeft', itemsleft,
            'status', json_audit->>'status',
            'deliveredAt', json_audit->>'deliveredat',
            'errors', json_audit->>'errors',
            'measurements', json_audit->'measurements',
            'plan', json_build_object(
              'key', json_audit->>'fk_plan',
              'name', json_plan->>'name',
              'description', json_plan->>'description',
              'limitationScope', json_plan->>'maxitems_scope',
              'limitationType', json_plan->>'maxitems_type',
              'maxitemsLimit', json_plan->>'maxitems'
            ),
            'project', CASE WHEN json_project is not null THEN json_build_object(
            'key', json_audit->>'fk_project',
            'name', json_project->>'name'
            ) ELSE json_build_object(
            'key', json_audit->>'fk_plan',
            'name', json_plan->>'name'
            ) END
          )
        ) INTO auditjson;
        
        RAISE NOTICE 'get_audit_information() auditjson: %', auditjson;
        RAISE NOTICE 'get_audit_information() Transaction ID: %', TXID_CURRENT();
          
      END
        
    $$;


ALTER PROCEDURE cognaio_audits.get_audit_information(IN audit_key uuid, IN plan_key uuid, OUT auditjson json) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 409 (class 1255 OID 28193)
-- Name: get_auditartifacts_extraction(uuid, text, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.get_auditartifacts_extraction(IN auditkey uuid, IN artifacts_type text, IN encryptionkey text, OUT artifact text)
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	if artifacts_type = 'fields' then
		SELECT cognaio_extensions.pgp_sym_decrypt(fields_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') INTO artifact
				FROM cognaio_audits.appkey_audit_artifacts_extraction  
				WHERE fk_audit = auditkey;
	end if;
	
	if artifacts_type = 'aientities' then
		SELECT cognaio_extensions.pgp_sym_decrypt(ai_entities_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') INTO artifact
				FROM cognaio_audits.appkey_audit_artifacts_extraction  
				WHERE fk_audit = auditkey;
	end if;
	
	if artifacts_type = 'aientitiesprompt' then
		SELECT cognaio_extensions.pgp_sym_decrypt(ai_entities_prompt, encryptionKey, 'compress-algo=1, cipher-algo=aes256') INTO artifact
				FROM cognaio_audits.appkey_audit_artifacts_extraction  
				WHERE fk_audit = auditkey;
	end if;
	
	if artifacts_type = 'feedback' then
		SELECT cognaio_extensions.pgp_sym_decrypt(feedback_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') INTO artifact
				FROM cognaio_audits.appkey_audit_artifacts_extraction  
				WHERE fk_audit = auditkey;
	end if;
END
$$;


ALTER PROCEDURE cognaio_audits.get_auditartifacts_extraction(IN auditkey uuid, IN artifacts_type text, IN encryptionkey text, OUT artifact text) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 420 (class 1255 OID 28194)
-- Name: get_auditartifacts_static_ocr(uuid, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.get_auditartifacts_static_ocr(IN auditkey uuid, IN encryptionkey text, OUT ocr_out json)
    LANGUAGE plpgsql
    AS $$
    DECLARE
      original_audit_ref_out uuid;
    BEGIN
        SELECT original_audit_ref
          , cognaio_extensions.pgp_sym_decrypt(ocr_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') 
        INTO original_audit_ref_out, ocr_out
            FROM cognaio_audits.appkey_audit_artifacts_static_ocr  
            WHERE fk_audit = auditkey;
            
        if original_audit_ref_out is not null then
          SELECT original_audit_ref
            , cognaio_extensions.pgp_sym_decrypt(ocr_results, encryptionKey, 'compress-algo=1, cipher-algo=aes256') 
          INTO original_audit_ref_out, ocr_out
              FROM cognaio_audits.appkey_audit_artifacts_static_ocr  
              WHERE fk_audit = original_audit_ref_out;
        end if;
    END
    $$;


ALTER PROCEDURE cognaio_audits.get_auditartifacts_static_ocr(IN auditkey uuid, IN encryptionkey text, OUT ocr_out json) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 400 (class 1255 OID 28195)
-- Name: get_envelope_artifact_binaries(uuid, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.get_envelope_artifact_binaries(IN artifactkey uuid, IN encryptionkey text, OUT artifact_binaries_out bytea)
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	SELECT cognaio_extensions.pgp_sym_decrypt_bytea(artifact_binaries, encryptionKey, 'compress-algo=1, cipher-algo=aes256') as artifact_binaries
	INTO artifact_binaries_out
			FROM cognaio_audits.envelope_artifact_audits  
			WHERE key = artifactkey;
END
$$;


ALTER PROCEDURE cognaio_audits.get_envelope_artifact_binaries(IN artifactkey uuid, IN encryptionkey text, OUT artifact_binaries_out bytea) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 401 (class 1255 OID 28196)
-- Name: get_envelope_header(uuid, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.get_envelope_header(IN envelope_key uuid, IN encryptionkey text, OUT envelope_header_out json)
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
	WITH sq AS
	(
		SELECT 
			key
			, fk_envelope
			, envelope_id
			, envelope_subject
			, envelope_from
			, envelope_to
			, envelope_cc
			, envelope_bcc
			, cognaio_extensions.pgp_sym_decrypt(decode(metadata, 'base64'), encryptionKey, 'compress-algo=1, cipher-algo=aes256') as metadata
			, createdat
		FROM cognaio_audits.envelope_audits WHERE key = envelope_key
	)
	SELECT json_agg(row_to_json(sq)) FROM sq INTO envelope_header_out;
END
$$;


ALTER PROCEDURE cognaio_audits.get_envelope_header(IN envelope_key uuid, IN encryptionkey text, OUT envelope_header_out json) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 402 (class 1255 OID 28197)
-- Name: lock_unlock_envelope_artifact_by_key(uuid, boolean, json); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.lock_unlock_envelope_artifact_by_key(IN artifactkey uuid, IN performlook boolean, IN parameters json, OUT artifactkey_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
	lock_token_in text; 
    lock_at_in timestamp;
    lock_expiresat_in timestamp;
	affectedItems integer;
BEGIN
    affectedItems := 0;
    if performlook = true then
		lock_at_in = (parameters->>'lockedat')::timestamp;
		lock_expiresat_in = (parameters->>'expiresat')::timestamp;
		lock_token_in = parameters->>'token';
	
		Update cognaio_audits.envelope_artifact_audits
			set lock_token = lock_token_in,
			lockedat = lock_at_in, 
			lock_expiresat = lock_expiresat_in WHERE key = artifactkey and lock_token IS NULL;

		GET DIAGNOSTICS affectedItems = ROW_COUNT;
  		RAISE NOTICE 'lock_unlock_envelope_artifact_by_key("lock") affectedItems: %', affectedItems;
		if affectedItems = 1 then
			artifactkey_out = artifactkey;
		end if;
	else
		lock_token_in = parameters->>'token';
	
		Update cognaio_audits.envelope_artifact_audits
			set lock_token = null,
			lockedat = null,  
			lock_expiresat = null WHERE key = artifactkey and lock_token = lock_token_in;

		GET DIAGNOSTICS affectedItems = ROW_COUNT;
  		RAISE NOTICE 'lock_unlock_envelope_artifact_by_key("lock") affectedItems: %', affectedItems;
		if affectedItems = 1 then
			artifactkey_out = artifactkey;
		end if;
    end if;
END
$$;


ALTER PROCEDURE cognaio_audits.lock_unlock_envelope_artifact_by_key(IN artifactkey uuid, IN performlook boolean, IN parameters json, OUT artifactkey_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 425 (class 1255 OID 38047)
-- Name: query_audits(uuid, json, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.query_audits(IN plan_key uuid, IN query_parameters json, IN encryptionkey text, OUT audit_keys_out uuid[])
    LANGUAGE plpgsql
    AS $_$
    DECLARE
    select_query text := 'WITH sqInner AS
      (
        SELECT fk_audit
          , cognaio_extensions.pgp_sym_decrypt(fields_results , $1 , ''compress-algo=1, cipher-algo=aes256'')::jsonb as fields_json
          , createdat
          , modifiedat
        FROM cognaio_audits.appkey_audit_artifacts_extraction fields
        INNER JOIN cognaio_audits.appkey_audits audits ON audits.key = fields.fk_audit
        AND audits.fk_plan = $2
      )
      SELECT a.fk_audit from sqInner a 
      LEFT JOIN jsonb_array_elements(a.fields_json) documents on true';
    where_clause_type text = '';
    where_clause_fields text = '';
    limit_clause text = '';
    query_field json;
    BEGIN        						  
      if query_parameters is not null then
        if query_parameters->>'document_type' is not null then 
          where_clause_type = format(where_clause_type || ' lower(documents->>''type'') = lower(%s)', quote_literal(query_parameters->>'document_type'));
        end if;			
        
        if query_parameters->>'fields' is not null and where_clause_type <> '' then
          where_clause_type = where_clause_type || ' AND ';
        end if;
        
        FOR query_field IN SELECT * FROM json_array_elements(query_parameters->'fields')
        LOOP
          if where_clause_fields <> '' then
            where_clause_fields = where_clause_fields || ' AND ';
          end if;
          where_clause_fields = format(where_clause_fields || 'documents->''fields'' @> ''[{"name":"%s"}]''', query_field->>'name');
          where_clause_fields = format(where_clause_fields || ' AND documents->''fields'' @> ''[{"value":"%s"}]''', query_field->>'value');
        END LOOP;	
        
        if query_parameters->>'top' is not null then 
          limit_clause = 'LIMIT %' || quote_literal(query_parameters->>'top');
        end if;
      end if;
      
      RAISE NOTICE 'query -> %', format('SELECT ARRAY(%s WHERE %s %s %s)', select_query, where_clause_type, where_clause_fields, limit_clause);
      EXECUTE format('SELECT ARRAY(%s WHERE %s %s %s)', select_query, where_clause_type, where_clause_fields, limit_clause) INTO audit_keys_out using encryptionkey, plan_key;
    END
      
  $_$;


ALTER PROCEDURE cognaio_audits.query_audits(IN plan_key uuid, IN query_parameters json, IN encryptionkey text, OUT audit_keys_out uuid[]) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 424 (class 1255 OID 30835)
-- Name: try_createorupdate_appkey_audit(uuid, uuid, text, integer, integer, text, json, json, text, text); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.try_createorupdate_appkey_audit(IN auditkey uuid, IN appkey uuid, IN docname text, IN documents integer, IN pages integer, IN ip text, IN externals_in json, IN measurements_in json, IN errors_in text, IN language text, OUT auditjson json)
    LANGUAGE plpgsql
    AS $$
        DECLARE
        timestamp_current timestamp;
        timestamp_min timestamp;
        timestamp_max timestamp;
        given_app_scope_key uuid; 
        given_app_plan_key uuid;  
        given_app_project_key uuid;  
        given_user_key uuid; 
        currentitems integer;
        requesteditems integer;
        itemsleft integer;
        itemsallowed integer;
        limitationtype text;
        limitationscope text;
        plan_name text;
        plan_desc text;
        external_audit_key uuid;
        external_orginal_page_count integer;
        auditkey_out uuid;
        outbound_json json;
        cleanup_cognaio_artifacts_enabled boolean;
        cleanup_cognaio_artifacts_interval_in_days integer;
        cleanup_cognaio_artifacts_max_deletion_limit integer;
        cleanup_envelope_artifacts_enabled boolean;
        cleanup_envelope_artifacts_interval_in_days integer;
        cleanup_envelope_artifacts_max_deletion_limit integer;
        cleanup_cognaio_embedding_artifacts_enabled boolean;
        cleanup_cognaio_embedding_artifacts_interval_in_days integer;
        cleanup_cognaio_embedding_artifacts_max_deletion_limit integer;
        documents_to_clean uuid[];
        affectedItems integer;
        original_audit_processing_started_at timestamp;
        original_audit_delivered_at timestamp;
        original_audit_historized_date timestamp;
        timestamp_historized_date timestamp;
        external_is_updatefromchainservice boolean;
        current_status cognaio_audits.audit_status;
        current_expires_early_at timestamp;
        cleanup_expired_cognaio_artifacts_enabled boolean;
        BEGIN
          -- set some defaults to cleanup of artifacts (always true & 7 days & 2 records to delete at once)
          cleanup_expired_cognaio_artifacts_enabled = TRUE;
          cleanup_cognaio_artifacts_enabled = TRUE;
          cleanup_cognaio_artifacts_interval_in_days = 7;
          cleanup_cognaio_artifacts_max_deletion_limit = 2;
          RAISE NOTICE 'cleanup_cognaio_artifacts - using default values for [enabled]=% and [interval in days]=% and [max deletion limit]=%'
            , cleanup_cognaio_artifacts_enabled, cleanup_cognaio_artifacts_interval_in_days, cleanup_cognaio_artifacts_max_deletion_limit;
          cleanup_envelope_artifacts_enabled = TRUE;
          cleanup_envelope_artifacts_interval_in_days = 7;
          cleanup_envelope_artifacts_max_deletion_limit = 2;
          RAISE NOTICE 'cleanup_envelope_artifacts - using default values for [enabled]=% and [interval in days]=% and [max deletion limit]=%'
            , cleanup_envelope_artifacts_enabled, cleanup_envelope_artifacts_interval_in_days, cleanup_envelope_artifacts_max_deletion_limit;
          cleanup_cognaio_embedding_artifacts_enabled = TRUE;
          cleanup_cognaio_embedding_artifacts_interval_in_days = 2;
          cleanup_cognaio_embedding_artifacts_max_deletion_limit = 10;
          RAISE NOTICE 'cleanup_cognaio_embedding_artifacts - using default values for [enabled]=% and [interval in days]=% and [max deletion limit]=%'
            , cleanup_cognaio_embedding_artifacts_enabled, cleanup_cognaio_embedding_artifacts_interval_in_days, cleanup_cognaio_embedding_artifacts_max_deletion_limit;
          ----------------------------
            
          timestamp_current = timezone('UTC', now());
          timestamp_historized_date = DATE_TRUNC('day', timestamp_current);
          
          given_app_plan_key = (externals_in->>'plan_key')::uuid;
          given_app_project_key = (externals_in->>'project_key')::uuid;
          plan_name = externals_in->>'plan_name';
          plan_desc = externals_in->>'plan_desc';
          given_user_key = (externals_in->>'user_key')::uuid;
          itemsallowed = externals_in->>'itemsallowed';
          limitationtype = externals_in->>'limitationtype';
          limitationscope = externals_in->>'limitationscope';
          external_audit_key = (externals_in->>'external_audit_key')::uuid;
          
          if externals_in->>'orginal_page_count' is null then
            external_orginal_page_count = 0;
          else 
            external_orginal_page_count = externals_in->>'orginal_page_count';
          end if;
        
          if(externals_in->>'isUpdateFromChainService' is null) then
            external_is_updatefromchainservice = false;
          else 
            external_is_updatefromchainservice = externals_in->>'isUpdateFromChainService';
          end if;
        
          if(externals_in->>'status' is not null) then
            current_status = (externals_in->>'status')::cognaio_audits.audit_status;
          end if;
        
          if(externals_in->>'expiresEarlyAt' is not null) then
            current_expires_early_at = externals_in->>'expiresEarlyAt';
          end if;
        
          if documents is null then
            documents = 0;
          end if;
            
          if(limitationscope = 'minute') then
              timestamp_min = date_trunc('minute', timestamp_current);
              timestamp_max = date_trunc('minute', timestamp_current + interval '1 minute');
          elsif (limitationscope = 'hour') then
              timestamp_min = date_trunc('hour', timestamp_current);
              timestamp_max = date_trunc('hour', timestamp_current + interval '1 hour');
          elsif (limitationscope = 'day') then
              timestamp_min = date_trunc('day', timestamp_current);
              timestamp_max = date_trunc('day', timestamp_current + interval '1 day');
          elsif (limitationscope = 'week') then
              timestamp_min = date_trunc('week', timestamp_current);
              timestamp_max = date_trunc('week', timestamp_current + interval '1 week');
          elsif (limitationscope = 'month') then
              timestamp_min = date_trunc('month', timestamp_current);
              timestamp_max = date_trunc('month', timestamp_current + interval '1 month');
          elsif (limitationscope = 'quarter') then
              timestamp_min = date_trunc('quarter', timestamp_current);
              timestamp_max = date_trunc('quarter', timestamp_current + interval '1 quarter');
          else
              timestamp_min = date_trunc('year', timestamp_current);
              timestamp_max = date_trunc('year', timestamp_current + interval '1 year');
          end if;
            
          RAISE NOTICE 'try_createorupdateAudit() timestamp_min: %', timestamp_min;
          RAISE NOTICE 'try_createorupdateAudit() timestamp_max: %', timestamp_max;
            
          if limitationtype = 'page' then
            requesteditems = pages;
            if limitationscope = 'hour' or limitationscope = 'minute' then
              SELECT sum(documentpagesarrived) INTO currentitems
                FROM cognaio_audits.appkey_audits  
                WHERE fk_plan = given_app_plan_key
                AND arrivedat between timestamp_min and timestamp_max;
              else
              SELECT sum(documentpagesarrived) INTO currentitems
                FROM cognaio_audits.appkey_audits_history 
                WHERE fk_plan = given_app_plan_key
                AND date between timestamp_min and timestamp_max;
                
              RAISE NOTICE 'try_createorupdateAudit() currentitems (%, page) from appkey_audits_history: %', limitationtype, currentitems;
            end if;
          else
            requesteditems = documents;
            if limitationscope = 'hour' or limitationscope = 'minute' then
              SELECT sum(documentsarrived) INTO currentitems
                FROM cognaio_audits.appkey_audits   
                WHERE fk_plan = given_app_plan_key
                AND arrivedat between timestamp_min and timestamp_max;
              else
              SELECT sum(documentsarrived) INTO currentitems
                FROM cognaio_audits.appkey_audits_history 
                WHERE fk_plan = given_app_plan_key
                AND date between timestamp_min and timestamp_max;
                
              RAISE NOTICE 'try_createorupdateAudit() currentitems (%, document) from appkey_audits_history: %', limitationtype, currentitems;
            end if;
          end if;
                
          if currentitems is null then
              currentitems = 0;
          end if;
        
          RAISE NOTICE 'try_createorupdateAudit() auditkey: %', auditkey;
          RAISE NOTICE 'try_createorupdateAudit() pages: %', pages;
          RAISE NOTICE 'try_createorupdateAudit() itemsallowed: %', itemsallowed;
          RAISE NOTICE 'try_createorupdateAudit() limitationtype: %', limitationtype;
          RAISE NOTICE 'try_createorupdateAudit() limitationscope: %', limitationscope;
          RAISE NOTICE 'try_createorupdateAudit() currentitems: %', currentitems;
          RAISE NOTICE 'try_createorupdateAudit() external_audit_key: %', external_audit_key;
          RAISE NOTICE 'try_createorupdateAudit() external_orginal_page_count: %', external_orginal_page_count;

          itemsleft = itemsallowed - currentitems - requesteditems;
        if auditkey = '00000000-0000-0000-0000-000000000000' or auditkey is null then
          if itemsleft > 0 then
            if external_audit_key = '00000000-0000-0000-0000-000000000000' or external_audit_key is null then
              INSERT INTO cognaio_audits.appkey_audits (fk_plan, fk_project, fk_user, documentname, status, documentsarrived, documentpagesarrived, orginal_page_count, receivedfrom_ip, historized_date, expiresearlyat)
                VALUES (given_app_plan_key, given_app_project_key, given_user_key, docname, current_status, documents, pages, external_orginal_page_count, ip, timestamp_historized_date, current_expires_early_at) 
                RETURNING key, status, expiresearlyat INTO auditkey_out, current_status, current_expires_early_at;
            else
              INSERT INTO cognaio_audits.appkey_audits (key, fk_plan, fk_project, fk_user, documentname, status, documentsarrived, documentpagesarrived, orginal_page_count, receivedfrom_ip, historized_date, expiresearlyat)
                VALUES (external_audit_key, given_app_plan_key, given_app_project_key, given_user_key, docname, current_status, documents, pages, external_orginal_page_count, ip, timestamp_historized_date, current_expires_early_at) 
                RETURNING key, status, expiresearlyat INTO auditkey_out, current_status, current_expires_early_at;
            end if;

            INSERT INTO cognaio_audits.appkey_audits_history (date, fk_plan, fk_project, fk_user, documentsarrived, documentpagesarrived, orginal_page_count)
              VALUES(timestamp_historized_date, given_app_plan_key, given_app_project_key, given_user_key, documents, pages, external_orginal_page_count) 
            ON CONFLICT (date, fk_plan, fk_project)
              DO 
              UPDATE SET documentsarrived = cognaio_audits.appkey_audits_history.documentsarrived + EXCLUDED.documentsarrived
                , documentpagesarrived = cognaio_audits.appkey_audits_history.documentpagesarrived + EXCLUDED.documentpagesarrived
                , orginal_page_count = cognaio_audits.appkey_audits_history.orginal_page_count + EXCLUDED.orginal_page_count
                , modifiedat = timestamp_current;
          end if;
        else
          if external_is_updatefromchainservice IS FALSE then
            UPDATE cognaio_audits.appkey_audits
              SET documentsdelivered = 1,
              documentpagesdelivered = pages,
              measurements = measurements_in, 
              errors = errors_in
              , expiresearlyat = NULL
              , status = CASE WHEN current_status is null THEN status ELSE current_status END
              , deliveredat = CASE WHEN deliveredat is null THEN timestamp_current ELSE deliveredat END
            WHERE key = auditkey 
              RETURNING processingstartedat, deliveredat, historized_date, status, expiresearlyat INTO 
                original_audit_processing_started_at, original_audit_delivered_at, original_audit_historized_date, current_status, current_expires_early_at;
              auditkey_out = auditkey;

            RAISE NOTICE 'try_createorupdateAudit() original_audit_delivered_at: %/% -> %', original_audit_delivered_at, timestamp_current, original_audit_delivered_at <> timestamp_current;

            UPDATE cognaio_audits.appkey_audits_history 
              SET documentsdelivered = documentsdelivered + CASE WHEN original_audit_delivered_at <> timestamp_current THEN 0 ELSE 1 END
                , documentpagesdelivered = documentpagesdelivered + CASE WHEN original_audit_delivered_at <> timestamp_current THEN 0 ELSE pages END
                , processing_duration_msec = processing_duration_msec + CASE WHEN original_audit_delivered_at <> timestamp_current THEN 0 ELSE EXTRACT(epoch from (timestamp_current - original_audit_processing_started_at))*1000 END
                , errors = errors + CASE WHEN errors_in is not null THEN 1 ELSE 0 END
                , modifiedat = timestamp_current
            WHERE date = original_audit_historized_date and fk_plan = given_app_plan_key and fk_project = given_app_project_key;
          else
            if errors_in is not null then
              UPDATE cognaio_audits.appkey_audits
                SET errors = errors_in
                  , status = CASE WHEN current_status is null THEN status ELSE current_status END
                  , expiresearlyat = NULL
              WHERE key = auditkey RETURNING status, expiresearlyat INTO current_status, current_expires_early_at; 
              auditkey_out = auditkey;
            elsif itemsleft > 0 then
              UPDATE cognaio_audits.appkey_audits
                SET documentsarrived = documentsarrived + documents
                , documentpagesarrived = documentpagesarrived + pages
                , orginal_page_count = orginal_page_count + pages
                , status = CASE WHEN current_status is null THEN status ELSE current_status END
                , processingstartedat = CASE WHEN current_status = 'processing' THEN timestamp_current ELSE processingstartedat END
                , expiresearlyat = CASE WHEN current_status = 'processing' THEN NULL ELSE expiresearlyat END
              WHERE key = auditkey RETURNING historized_date, status, expiresearlyat INTO original_audit_historized_date, current_status, current_expires_early_at;
              
              UPDATE cognaio_audits.appkey_audits_history 
              SET documentsarrived = documentsarrived + documents
                , documentpagesarrived = documentpagesarrived + pages
                , orginal_page_count = orginal_page_count + pages
                , modifiedat = timestamp_current
              WHERE date = original_audit_historized_date and fk_plan = given_app_plan_key and fk_project = given_app_project_key;

              auditkey_out = auditkey;
            end if;
          end if;
        end if;

        SELECT json_build_object(
            'key', auditkey_out,
            'name', docname,
            'timestamp', timestamp_current,
            'itemsLeft', itemsleft,
            'status', current_status,
            'plan', json_build_object(
              'key', given_app_plan_key,
              'name', plan_name,
              'description', plan_desc,
              'limitationScope', limitationscope,
              'limitationType', limitationtype,
              'maxitemsLimit', itemsallowed
            )
        ) INTO auditjson;
      
        RAISE NOTICE 'try_createorupdateAudit() auditjson: %', auditjson;
        RAISE NOTICE 'try_createorupdateAudit() Transaction ID: %', TXID_CURRENT();
          
        if auditkey = '00000000-0000-0000-0000-000000000000' or auditkey is null then
          SELECT outbound_def INTO outbound_json FROM cognaio_design.def_process_mappings mapping JOIN cognaio_design.def_process_outbounds outbound ON mapping.fk_outbound_def = outbound.key WHERE mapping.fk_plan = given_app_plan_key AND mapping.disabledat IS NULL LIMIT 1;
          
          IF outbound_json::jsonb->'auditArtifacts'?'cleanup' THEN
          
            IF outbound_json::jsonb -> 'auditArtifacts'->'cleanup'?'cognaioAudits' THEN
              IF (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'cognaioAudits'->'enabled') IS NOT NULL Then
                cleanup_cognaio_artifacts_enabled := (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'cognaioAudits'->'enabled')::boolean;
                RAISE NOTICE 'cleanup_cognaio_artifacts - overwriting defaults with values from process definition for [enabled]=%'
                  , cleanup_cognaio_artifacts_enabled;
              END IF;
              
              IF (outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'cognaioAudits'->'intervalInDays') IS NOT NULL Then
                cleanup_cognaio_artifacts_interval_in_days := outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'cognaioAudits'->'intervalInDays';
                RAISE NOTICE 'cleanup_cognaio_artifacts - overwriting defaults with values from process definition for [interval in days]=%'
                  , cleanup_cognaio_artifacts_interval_in_days;
              END IF;
            END IF;
            
            -- envelopeArtifacts
            IF outbound_json::jsonb -> 'auditArtifacts'->'cleanup'?'envelopeArtifacts' THEN
              IF (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'envelopeArtifacts'->'enabled') IS NOT NULL Then
                cleanup_envelope_artifacts_enabled := (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'envelopeArtifacts'->'enabled')::boolean;
                RAISE NOTICE 'cleanup_envelope_artifacts - overwriting defaults with values from process definition for [enabled]=%'
                  , cleanup_envelope_artifacts_enabled;
              END IF;
              
              IF (outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'envelopeArtifacts'->'intervalInDays') IS NOT NULL Then
                cleanup_envelope_artifacts_interval_in_days := outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'envelopeArtifacts'->'intervalInDays';
                RAISE NOTICE 'cleanup_envelope_artifacts - overwriting defaults with values from process definition for [interval in days]=%'
                  , cleanup_envelope_artifacts_interval_in_days;
              END IF;
            END IF;
            
            -- embeddingArtifacts
            IF outbound_json::jsonb -> 'auditArtifacts'->'cleanup'?'embeddingArtifacts' THEN
              IF (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'embeddingArtifacts'->'enabled') IS NOT NULL Then
                cleanup_envelope_artifacts_enabled := (outbound_json::jsonb -> 'auditArtifacts'->'cleanup'->'embeddingArtifacts'->'enabled')::boolean;
                RAISE NOTICE 'cleanup_embedding_artifacts - overwriting defaults with values from process definition for [enabled]=%'
                  , cleanup_cognaio_embedding_artifacts_enabled;
              END IF;
              
              IF (outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'embeddingArtifacts'->'intervalInDays') IS NOT NULL Then
                cleanup_envelope_artifacts_interval_in_days := outbound_json::jsonb ->'auditArtifacts'->'cleanup'->'embeddingArtifacts'->'intervalInDays';
                RAISE NOTICE 'cleanup_embedding_artifacts - overwriting defaults with values from process definition for [interval in days]=%'
                  , cleanup_cognaio_embedding_artifacts_interval_in_days;
              END IF;
            END IF;
            
          END IF;
          
          IF cleanup_cognaio_artifacts_enabled IS TRUE AND cleanup_cognaio_artifacts_interval_in_days > 0 THEN				
            RAISE NOTICE 'Cleaning some old cognaio audit records (older than % day(s)) ...' , cleanup_cognaio_artifacts_interval_in_days;
            documents_to_clean := ARRAY(SELECT key FROM cognaio_audits.appkey_audits
                          WHERE fk_plan = given_app_plan_key AND arrivedat < (timestamp_current - cleanup_cognaio_artifacts_interval_in_days * INTERVAL'1 day') LIMIT cleanup_cognaio_artifacts_max_deletion_limit);
            IF array_length(documents_to_clean, 1) is NULL THEN	   
              RAISE NOTICE 'Didnt find documents to remove';
            ELSE
              RAISE NOTICE 'Found % documents to remove', array_length (documents_to_clean, 1);
            END IF;

            DELETE FROM cognaio_audits.appkey_audit_artifacts_static_image WHERE fk_audit = ANY(documents_to_clean);
            DELETE FROM cognaio_audits.appkey_audit_artifacts_static_ocr WHERE fk_audit = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % static artifact(s)', affectedItems;
            
            DELETE FROM cognaio_audits.appkey_audit_artifacts_extraction WHERE fk_audit = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % extraction artifact(s)', affectedItems;	

            DELETE FROM cognaio_audits.appkey_audits WHERE key = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % audit(s)', affectedItems;
          ELSE
            RAISE NOTICE 'Skipping cognaio audit cleanup due to the following parameter [enabled]=% and [interval in days]=% ...'
              , cleanup_cognaio_artifacts_enabled, cleanup_cognaio_artifacts_interval_in_days;
          END IF;

          IF cleanup_expired_cognaio_artifacts_enabled IS TRUE THEN				
            RAISE NOTICE 'Cleaning some expired cognaio audit records ...';
            documents_to_clean := ARRAY(SELECT key FROM cognaio_audits.appkey_audits
                          WHERE fk_plan = given_app_plan_key AND expiresearlyat IS NOT NULL AND expiresearlyat < timestamp_current LIMIT cleanup_cognaio_artifacts_max_deletion_limit);
            IF array_length(documents_to_clean, 1) is NULL THEN	   
              RAISE NOTICE 'Didnt find documents to remove';
            ELSE
              RAISE NOTICE 'Found % documents to remove', array_length (documents_to_clean, 1);
            END IF;

            DELETE FROM cognaio_audits.appkey_audit_artifacts_static_image WHERE fk_audit = ANY(documents_to_clean);
            DELETE FROM cognaio_audits.appkey_audit_artifacts_static_ocr WHERE fk_audit = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % static artifact(s)', affectedItems;
            
            DELETE FROM cognaio_audits.appkey_audit_artifacts_extraction WHERE fk_audit = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % extraction artifact(s)', affectedItems;	

            DELETE FROM cognaio_audits.appkey_audits WHERE key = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % audit(s)', affectedItems;
          ELSE
            RAISE NOTICE 'Skipping expired cognaio audit cleanup due to the following parameter [enabled]=%  ...'
              , cleanup_expired_cognaio_artifacts_enabled;
          END IF;
          
          IF cleanup_envelope_artifacts_enabled IS TRUE AND cleanup_envelope_artifacts_interval_in_days > 0 THEN	
            RAISE NOTICE 'Cleaning some old envelopes and their artifacts records (older than % day(s)) ...' , cleanup_envelope_artifacts_interval_in_days;
            
            documents_to_clean := ARRAY(SELECT key FROM cognaio_audits.envelope_audits
                          WHERE fk_plan = given_app_plan_key AND createdat < (timestamp_current - cleanup_cognaio_artifacts_interval_in_days * INTERVAL'1 day') LIMIT cleanup_cognaio_artifacts_max_deletion_limit);
						  
            IF array_length(documents_to_clean, 1) is NULL THEN	   
              RAISE NOTICE 'Didnt find documents to remove';
            ELSE
              RAISE NOTICE 'Found % documents to remove', array_length (documents_to_clean, 1);
            END IF;

            DELETE FROM cognaio_audits.envelope_artifact_audits 
            WHERE cognaio_audits.envelope_artifact_audits.fk_envelope = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % envelope artifact(s)', affectedItems;

            DELETE FROM cognaio_audits.envelope_audits 
            WHERE cognaio_audits.envelope_audits.key = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % envelope(s)', affectedItems;
          ELSE
            RAISE NOTICE 'Skipping envelope artifacts cleanup due to the following parameter [enabled]=% and [interval in days]=% ...'
              , cleanup_envelope_artifacts_enabled, cleanup_envelope_artifacts_interval_in_days;
          END IF;
          
          IF cleanup_cognaio_embedding_artifacts_enabled IS TRUE AND cleanup_cognaio_embedding_artifacts_interval_in_days > 0 THEN	
            RAISE NOTICE 'Cleaning some old cognaio embedding artifacts records (older than % day(s)) ...' , cleanup_cognaio_embedding_artifacts_interval_in_days;
            
            documents_to_clean := ARRAY(SELECT DISTINCT b.key FROM cognaio_audits.appkey_audit_artifacts_embeddings as a 
                          INNER JOIN cognaio_audits.appkey_audits b ON a.fk_audit = b.key
                          WHERE a.createdat < (timestamp_current - cleanup_cognaio_embedding_artifacts_interval_in_days * INTERVAL'1 day') AND b.fk_plan = given_app_plan_key LIMIT cleanup_cognaio_embedding_artifacts_max_deletion_limit);
            IF array_length(documents_to_clean, 1) is NULL THEN	   
              RAISE NOTICE 'Didnt find documents to remove';
            ELSE
              RAISE NOTICE 'Found % documents to remove', array_length (documents_to_clean, 1);
            END IF;

            DELETE FROM cognaio_audits.appkey_audit_artifacts_embeddings 
            WHERE cognaio_audits.appkey_audit_artifacts_embeddings.fk_audit = ANY(documents_to_clean);

            GET DIAGNOSTICS affectedItems = ROW_COUNT;
            RAISE NOTICE 'Removed % envelope artifact(s)', affectedItems;
          ELSE
            RAISE NOTICE 'Skipping cognaio embeddings artifacts cleanup due to the following parameter [enabled]=% and [interval in days]=% ...'
              , cleanup_cognaio_embedding_artifacts_enabled, cleanup_cognaio_embedding_artifacts_interval_in_days;
          END IF;
        end if;
          
      END
        
    
$$;


ALTER PROCEDURE cognaio_audits.try_createorupdate_appkey_audit(IN auditkey uuid, IN appkey uuid, IN docname text, IN documents integer, IN pages integer, IN ip text, IN externals_in json, IN measurements_in json, IN errors_in text, IN language text, OUT auditjson json) OWNER TO postgres;

--
-- TOC entry 403 (class 1255 OID 28200)
-- Name: unlock_envelope_artifacts_expired(uuid); Type: PROCEDURE; Schema: cognaio_audits; Owner: postgres
--

CREATE PROCEDURE cognaio_audits.unlock_envelope_artifacts_expired(IN mailboxkey uuid, OUT affecteditems integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    affectedItems := 0;
	
	UPDATE cognaio_audits.envelope_artifact_audits updateenvelopes
		SET lock_token = null, 
		lockedat = null, 
		lock_expiresat = null
		FROM cognaio_audits.envelope_artifact_audits env_artifacts
			INNER JOIN cognaio_audits.envelope_audits env ON env_artifacts.fk_envelope = env.key
			And env_artifacts.lock_expiresat IS NOT NULL AND env_artifacts.lock_expiresat < timezone('UTC', now())
			AND env.fk_mailbox_key = mailboxkey
		WHERE env_artifacts.fk_envelope = env.key;
		
	GET DIAGNOSTICS affectedItems = ROW_COUNT;
	RAISE NOTICE 'unlock_envelope_artifacts_expired() affectedItems: %', affectedItems;
END
$$;


ALTER PROCEDURE cognaio_audits.unlock_envelope_artifacts_expired(IN mailboxkey uuid, OUT affecteditems integer) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 251 (class 1259 OID 28201)
-- Name: appkey_audit_artifacts_embeddings; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audit_artifacts_embeddings (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_audit uuid NOT NULL,
    content text,
    embedding cognaio_extensions.vector,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_audits.appkey_audit_artifacts_embeddings OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 252 (class 1259 OID 28208)
-- Name: appkey_audit_artifacts_extraction; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audit_artifacts_extraction (
    fk_audit uuid NOT NULL,
    fields_results bytea,
    ai_entities_results bytea,
    ai_entities_prompt bytea,
    feedback_results bytea,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_audits.appkey_audit_artifacts_extraction OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 253 (class 1259 OID 28214)
-- Name: appkey_audit_artifacts_static_ocr; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audit_artifacts_static_ocr (
    fk_audit uuid NOT NULL,
    original_audit_ref uuid,
    ocr_results bytea,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_audits.appkey_audit_artifacts_static_ocr OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 254 (class 1259 OID 28220)
-- Name: appkey_audits; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audits (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_app_key uuid,
    fk_user uuid NOT NULL,
    fk_plan uuid NOT NULL,
    documentname text NOT NULL,
    documentsarrived integer DEFAULT 0 NOT NULL,
    documentsdelivered integer DEFAULT 0 NOT NULL,
    documentpagesarrived integer DEFAULT 0 NOT NULL,
    documentpagesdelivered integer DEFAULT 0 NOT NULL,
    measurements json,
    errors text,
    receivedfrom_ip character varying(255) NOT NULL,
    arrivedat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    deliveredat timestamp without time zone,
    orginal_page_count integer DEFAULT 0 NOT NULL,
    historized_date timestamp without time zone,
    fk_project uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid NOT NULL,
    processingstartedat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    status cognaio_audits.audit_status,
    expiresearlyat timestamp without time zone
);


ALTER TABLE cognaio_audits.appkey_audits OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 255 (class 1259 OID 28233)
-- Name: appkey_audits_history; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.appkey_audits_history (
    date timestamp without time zone DEFAULT date_trunc('day'::text, timezone('UTC'::text, now())) NOT NULL,
    orginal_page_count integer DEFAULT 0 NOT NULL,
    documentsarrived integer DEFAULT 0 NOT NULL,
    documentsdelivered integer DEFAULT 0 NOT NULL,
    documentpagesarrived integer DEFAULT 0 NOT NULL,
    documentpagesdelivered integer DEFAULT 0 NOT NULL,
    processing_duration_msec bigint DEFAULT 0 NOT NULL,
    errors integer DEFAULT 0 NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    fk_app_key uuid,
    fk_plan uuid NOT NULL,
    fk_user uuid NOT NULL,
    fk_project uuid DEFAULT '00000000-0000-0000-0000-000000000000'::uuid NOT NULL
);


ALTER TABLE cognaio_audits.appkey_audits_history OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 256 (class 1259 OID 28246)
-- Name: envelope_artifact_audits; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.envelope_artifact_audits (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_envelope uuid,
    audit_key uuid NOT NULL,
    artifact_name text,
    artifact_content_type text,
    status cognaio_audits.envelope_artifact_status DEFAULT 'created'::cognaio_audits.envelope_artifact_status NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    processingstartedat timestamp without time zone,
    doneat timestamp without time zone,
    donewitherrorsat timestamp without time zone,
    processing_audits json DEFAULT '[]'::json,
    lockedat timestamp without time zone,
    lock_token text,
    lock_expiresat timestamp without time zone,
    artifact_binaries bytea
);


ALTER TABLE cognaio_audits.envelope_artifact_audits OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 257 (class 1259 OID 28255)
-- Name: envelope_audits; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.envelope_audits (
    key uuid NOT NULL,
    fk_mailbox_key uuid NOT NULL,
    fk_app_key uuid NOT NULL,
    fk_user uuid NOT NULL,
    fk_plan uuid NOT NULL,
    fk_envelope uuid,
    envelope_id text NOT NULL,
    envelope_subject text NOT NULL,
    envelope_from text NOT NULL,
    envelope_to text NOT NULL,
    envelope_cc text,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    metadata text,
    envelope_bcc text
);


ALTER TABLE cognaio_audits.envelope_audits OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 258 (class 1259 OID 28261)
-- Name: schema_versions; Type: TABLE; Schema: cognaio_audits; Owner: postgres
--

CREATE TABLE cognaio_audits.schema_versions (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    version text NOT NULL,
    description text,
    appliedat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_audits.schema_versions OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 3638 (class 2606 OID 28269)
-- Name: appkey_audit_artifacts_extraction app_audit_artifacts_extraction_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_extraction
    ADD CONSTRAINT app_audit_artifacts_extraction_pkey PRIMARY KEY (fk_audit);


--
-- TOC entry 3640 (class 2606 OID 28271)
-- Name: appkey_audit_artifacts_static_ocr app_audit_artifacts_static_ocr_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_ocr
    ADD CONSTRAINT app_audit_artifacts_static_ocr_pkey PRIMARY KEY (fk_audit);


--
-- TOC entry 3643 (class 2606 OID 28273)
-- Name: appkey_audits app_processruns_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audits
    ADD CONSTRAINT app_processruns_pkey PRIMARY KEY (key);


--
-- TOC entry 3634 (class 2606 OID 28275)
-- Name: appkey_audit_artifacts_static_image appkey_audit_artifacts_static_image_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_image
    ADD CONSTRAINT appkey_audit_artifacts_static_image_pkey PRIMARY KEY (key);


--
-- TOC entry 3645 (class 2606 OID 28277)
-- Name: appkey_audits_history appkey_audits_history_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audits_history
    ADD CONSTRAINT appkey_audits_history_pkey PRIMARY KEY (date, fk_plan, fk_project);


--
-- TOC entry 3636 (class 2606 OID 28279)
-- Name: appkey_audit_artifacts_embeddings embeddings_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_embeddings
    ADD CONSTRAINT embeddings_pkey PRIMARY KEY (key);


--
-- TOC entry 3647 (class 2606 OID 28281)
-- Name: envelope_artifact_audits envelope_artifact_audits_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.envelope_artifact_audits
    ADD CONSTRAINT envelope_artifact_audits_pkey PRIMARY KEY (key);


--
-- TOC entry 3649 (class 2606 OID 28283)
-- Name: envelope_audits envelope_audits_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.envelope_audits
    ADD CONSTRAINT envelope_audits_pkey PRIMARY KEY (key);


--
-- TOC entry 3652 (class 2606 OID 28285)
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (key);


--
-- TOC entry 3632 (class 1259 OID 28286)
-- Name: appkey_audit_artifacts_static_image_fk_audit_idx; Type: INDEX; Schema: cognaio_audits; Owner: postgres
--

CREATE INDEX appkey_audit_artifacts_static_image_fk_audit_idx ON cognaio_audits.appkey_audit_artifacts_static_image USING btree (fk_audit);


--
-- TOC entry 3641 (class 1259 OID 28287)
-- Name: appkey_audit_artifacts_static_ocr_fk_audit_idx; Type: INDEX; Schema: cognaio_audits; Owner: postgres
--

CREATE INDEX appkey_audit_artifacts_static_ocr_fk_audit_idx ON cognaio_audits.appkey_audit_artifacts_static_ocr USING btree (fk_audit);


--
-- TOC entry 3650 (class 1259 OID 28288)
-- Name: schema_version_number; Type: INDEX; Schema: cognaio_audits; Owner: postgres
--

CREATE UNIQUE INDEX schema_version_number ON cognaio_audits.schema_versions USING btree (lower(version));

--
-- TOC entry 3656 (class 2606 OID 28289)
-- Name: appkey_audit_artifacts_extraction audit_fk; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_extraction
    ADD CONSTRAINT audit_fk FOREIGN KEY (fk_audit) REFERENCES cognaio_audits.appkey_audits(key);


--
-- TOC entry 3653 (class 2606 OID 28294)
-- Name: appkey_audit_artifacts_static_image audit_fk; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_image
    ADD CONSTRAINT audit_fk FOREIGN KEY (fk_audit) REFERENCES cognaio_audits.appkey_audits(key);


--
-- TOC entry 3657 (class 2606 OID 28299)
-- Name: appkey_audit_artifacts_static_ocr audit_fk; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_ocr
    ADD CONSTRAINT audit_fk FOREIGN KEY (fk_audit) REFERENCES cognaio_audits.appkey_audits(key);


--
-- TOC entry 3655 (class 2606 OID 28304)
-- Name: appkey_audit_artifacts_embeddings fk_audit; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_embeddings
    ADD CONSTRAINT fk_audit FOREIGN KEY (fk_audit) REFERENCES cognaio_audits.appkey_audits(key) ON DELETE CASCADE NOT VALID;


--
-- TOC entry 3659 (class 2606 OID 28309)
-- Name: envelope_audits fk_envelope; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.envelope_audits
    ADD CONSTRAINT fk_envelope FOREIGN KEY (fk_envelope) REFERENCES cognaio_audits.envelope_audits(key) NOT VALID;


--
-- TOC entry 3654 (class 2606 OID 28314)
-- Name: appkey_audit_artifacts_static_image orginal_audit_ref; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_image
    ADD CONSTRAINT orginal_audit_ref FOREIGN KEY (original_audit_ref) REFERENCES cognaio_audits.appkey_audits(key) ON DELETE CASCADE;


--
-- TOC entry 3658 (class 2606 OID 28319)
-- Name: appkey_audit_artifacts_static_ocr orginal_audit_ref; Type: FK CONSTRAINT; Schema: cognaio_audits; Owner: postgres
--

ALTER TABLE ONLY cognaio_audits.appkey_audit_artifacts_static_ocr
    ADD CONSTRAINT orginal_audit_ref FOREIGN KEY (original_audit_ref) REFERENCES cognaio_audits.appkey_audits(key) ON DELETE CASCADE;
    

INSERT INTO cognaio_audits.schema_versions (version, description) VALUES ('2.2.0.0', 'cognaio version 2.2');


-- Completed on 2024-04-09 17:25:03

--
-- PostgreSQL database dump complete
--

