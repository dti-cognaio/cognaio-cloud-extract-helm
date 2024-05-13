--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4 (Debian 15.4-2.pgdg120+1)
-- Dumped by pg_dump version 15.2

-- Started on 2024-04-09 17:28:53

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
-- TOC entry 11 (class 2615 OID 27685)
-- Name: cognaio_design; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA cognaio_design;


ALTER SCHEMA cognaio_design OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 1049 (class 1247 OID 27687)
-- Name: plan_limitation_scope; Type: TYPE; Schema: cognaio_design; Owner: postgres
--

CREATE TYPE cognaio_design.plan_limitation_scope AS ENUM (
    'minute',
    'hour',
    'day',
    'week',
    'month',
    'year',
    'quarter'
);


ALTER TYPE cognaio_design.plan_limitation_scope OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 1052 (class 1247 OID 27702)
-- Name: plan_limitation_type; Type: TYPE; Schema: cognaio_design; Owner: postgres
--

CREATE TYPE cognaio_design.plan_limitation_type AS ENUM (
    'page',
    'document'
);


ALTER TYPE cognaio_design.plan_limitation_type OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 1055 (class 1247 OID 27708)
-- Name: plan_type; Type: TYPE; Schema: cognaio_design; Owner: postgres
--

CREATE TYPE cognaio_design.plan_type AS ENUM (
    'api',
    'ui'
);


ALTER TYPE cognaio_design.plan_type OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 411 (class 1255 OID 27713)
-- Name: crypto(text, text, text, text); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.crypto(IN kind text, IN input_text text, IN secret text, IN encryption_key text, OUT content_out text)
    LANGUAGE plpgsql
    AS $$
DECLARE
	hmac_key text;
BEGIN
	hmac_key = encode(cognaio_extensions.hmac(secret, encryption_key, 'sha256'), 'hex');
	
	if kind = 'encrypt' then
		content_out = encode(cognaio_extensions.pgp_sym_encrypt(input_text, hmac_key, 'compress-algo=1, cipher-algo=aes256'), 'base64');
	elsif kind = 'decrypt' then
		content_out = cognaio_extensions.pgp_sym_decrypt(decode(input_text, ('base64')), hmac_key, 'compress-algo=1, cipher-algo=aes256');
	end if;
	
END
$$;


ALTER PROCEDURE cognaio_design.crypto(IN kind text, IN input_text text, IN secret text, IN encryption_key text, OUT content_out text) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 412 (class 1255 OID 27714)
-- Name: lock_unlock_mailbox_by_key(uuid, boolean, json); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.lock_unlock_mailbox_by_key(IN boxkey uuid, IN performlook boolean, IN parameters json, OUT boxkey_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
	lockedby_boxmapping_in uuid; 
	lockedby_user_in uuid; 
	lock_token_in text; 
    lock_at_in timestamp;
    lock_expiresat_in timestamp;
	affectedboxes integer;
BEGIN
    affectedboxes := 0;
    if performlook = true then
		lockedby_boxmapping_in = (parameters->>'boxmapping')::uuid;
		lockedby_user_in = (parameters->>'user')::uuid;
		lock_at_in = (parameters->>'lockedat')::timestamp;
		lock_expiresat_in = (parameters->>'expiresat')::timestamp;
		lock_token_in = parameters->>'token';
	
		Update cognaio_design.def_process_mailboxes
			set lock_token = lock_token_in,
			lockedby_user = lockedby_user_in,
			lockedby_boxmapping = lockedby_boxmapping_in, 
			lockedat = lock_at_in, 
			lock_expiresat = lock_expiresat_in WHERE key = boxkey and lock_token IS NULL;

		GET DIAGNOSTICS affectedboxes = ROW_COUNT;
  		RAISE NOTICE 'lock_unlock_mailbox_by_key("lock") affectedboxes: %', affectedboxes;
		if affectedboxes = 1 then
			boxkey_out = boxkey;
		end if;
	else
		lock_token_in = parameters->>'token';
	
		Update cognaio_design.def_process_mailboxes
			set lock_token = null,
			lockedby_user = null,
			lockedby_boxmapping = null,
			lockedat = null,  
			lock_expiresat = null WHERE key = boxkey and lock_token = lock_token_in;

		GET DIAGNOSTICS affectedboxes = ROW_COUNT;
  		RAISE NOTICE 'lock_unlock_mailbox_by_key("lock") affectedboxes: %', affectedboxes;
		if affectedboxes = 1 then
			boxkey_out = boxkey;
		end if;
    end if;
END
$$;


ALTER PROCEDURE cognaio_design.lock_unlock_mailbox_by_key(IN boxkey uuid, IN performlook boolean, IN parameters json, OUT boxkey_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 413 (class 1255 OID 27715)
-- Name: organization_createorupdate(json, uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.organization_createorupdate(IN organization_options json, IN userkey uuid, OUT key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	existing_organization_key uuid;
	existing_organization_parent_key uuid;
	existing_organization_name text;
	existing_organization_description text;
	existing_organization_logo text;
BEGIN
    timestamp_current = timezone('UTC', now());
	existing_organization_key = (organization_options->>'key')::uuid;
	existing_organization_parent_key = (organization_options->>'parent')::uuid;
	existing_organization_name = (organization_options->>'name')::text;
	existing_organization_description = (organization_options->>'description')::text;
	existing_organization_logo = (organization_options->>'logo')::text;
	
	if existing_organization_key is null then
		INSERT INTO cognaio_design.app_organizations (
		fk_parent_organization, name, description, logo_base64, createdby
		) VALUES(
			existing_organization_parent_key
			, existing_organization_name
			, existing_organization_description
			, existing_organization_logo
			, userkey
		) RETURNING key INTO key_out;
	else
		UPDATE cognaio_design.app_organizations
			SET fk_parent_organization = CASE WHEN existing_organization_parent_key is not null THEN existing_organization_parent_key ELSE fk_parent_organization END
			, name = CASE WHEN existing_organization_name is not null THEN existing_organization_name ELSE name END
			, description = CASE WHEN existing_organization_description is not null THEN existing_organization_description ELSE description END
			, logo_base64 = CASE WHEN existing_organization_logo is not null THEN existing_organization_logo ELSE logo_base64 END
			, modifiedat = timestamp_current
			, modifiedby = userkey
		WHERE key = existing_organization_key RETURNING key INTO key_out;
	end if;
END
$$;


ALTER PROCEDURE cognaio_design.organization_createorupdate(IN organization_options json, IN userkey uuid, OUT key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 414 (class 1255 OID 27716)
-- Name: organization_delete(json, uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.organization_delete(IN organizationkeys json, IN userkey uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
  timestamp_current timestamp;
	endpoints_to_delete uuid[];
	outbounds_to_delete uuid[];
  organization_keys uuid[];
  organization_key uuid;
BEGIN
  timestamp_current = timezone('UTC', now());
	organization_keys = ARRAY(select json_array_elements_text(organizationkeys->'keys'));
	FOREACH organization_key IN ARRAY organization_keys
    loop
		RAISE notice '%', organization_key;
		UPDATE cognaio_design.app_organizations
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE key = organization_key and disabledat is null;
		
		UPDATE cognaio_design.app_organization_users
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_organization_key = organization_key and disabledat is null;
		
		UPDATE cognaio_design.app_registration_requests
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_organization = organization_key and disabledat is null;
		
		UPDATE cognaio_design.app_keys
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_plan in (
			SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
				SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
			)
		) and disabledat is null;
		
		endpoints_to_delete := ARRAY(SELECT fk_endpoints_def FROM cognaio_design.def_process_mappings		
			WHERE fk_plan in (
				SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
					SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
				)
			) and disabledat is null
		);
		
		outbounds_to_delete := ARRAY(SELECT fk_outbound_def FROM cognaio_design.def_process_mappings		
			WHERE fk_plan in (
				SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
					SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
				)
			) and disabledat is null
		);
		
		UPDATE cognaio_design.def_process_endpoints
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE key = ANY(endpoints_to_delete) and disabledat is null;
		
		UPDATE cognaio_design.def_process_outbounds
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE key = ANY(outbounds_to_delete) and disabledat is null;
		
		UPDATE cognaio_design.def_process_mappings
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_plan in (
			SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
				SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
			)
		) and disabledat is null;
		
		UPDATE cognaio_design.def_process_projects
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_plan in (
			SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
				SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
			)
		) and disabledat is null;
		
		UPDATE cognaio_design.app_plans
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE fk_scope in (
			SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
		) and disabledat is null;
		
		UPDATE cognaio_design.app_scopes
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE key in (
			SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
		) and disabledat is null;
		
		UPDATE cognaio_design.app_organization_scopes
			SET disabledat = timestamp_current
			, disabledby = userkey
		WHERE key in (
			SELECT key FROM cognaio_design.app_organization_scopes WHERE fk_organization_key = organization_key AND disabledat is null
		) and disabledat is null;
	
    end loop;
	
END
$$;


ALTER PROCEDURE cognaio_design.organization_delete(IN organizationkeys json, IN userkey uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 415 (class 1255 OID 27717)
-- Name: plan_createorupdate(json, uuid, text, text); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.plan_createorupdate(IN plan_options json, IN userkey uuid, IN encryptionkey_template_endpoint text, IN encryptionkey_endpoint text, OUT key_out uuid)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    timestamp_current timestamp;
	existing_plan_key uuid;
	existing_scope_parent_key uuid;
	existing_plan_name text;
	existing_plan_description text;
	existing_plan_maxItems integer;
	existing_plan_maxItemsScope_text text;
	existing_plan_maxItemsScope cognaio_design.plan_limitation_scope;
	existing_plan_appkey_expiration_in_minutes integer;
	
	current_endpoint_value text;
	endpoint_name text;
	endpoint_key uuid;
	current_scope_name text;
	current_outbound_value json;
	outbound_name text;
	outbound_key uuid;
	mapping_name text;
BEGIN
    timestamp_current = timezone('UTC', now());
	existing_plan_key = (plan_options->>'key')::uuid;
	existing_scope_parent_key = (plan_options->>'parent')::uuid;
	existing_plan_name = (plan_options->>'name')::text;
	existing_plan_description = (plan_options->>'description')::text;
	existing_plan_maxItems = (plan_options->>'max_items')::integer;
	existing_plan_maxItemsScope_text = (plan_options->>'max_items_scope')::text;
	existing_plan_appkey_expiration_in_minutes = (plan_options->>'appkey_expiration_in_minutes')::integer;
	
	SELECT name INTO current_scope_name
		from cognaio_design.app_scopes WHERE key = existing_scope_parent_key AND disabledat is null LIMIT 1;
		
	if current_scope_name is null then
		RAISE EXCEPTION 'Nonexistent scope'
			USING HINT = 'Please check your scopes';
	end if;
		
	if existing_plan_maxItemsScope_text is null or existing_plan_maxItemsScope_text !~* '^(minute|hour|day|week|month|year)$' then
		existing_plan_maxItemsScope = 'day'::plan_limitation_scope;
	else
		existing_plan_maxItemsScope = existing_plan_maxItemsScope_text::plan_limitation_scope;
	end if;
	
	if existing_plan_key is null then
		SELECT outbound INTO current_outbound_value
			from cognaio_design.app_templates_outbound WHERE disabledat is null Order by createdat desc LIMIT 1;
		
		if current_outbound_value is null then
			RAISE EXCEPTION 'Nonexistent outbound template'
      			USING HINT = 'Please check your outbound templates';
		end if;
		
		SELECT cognaio_extensions.pgp_sym_decrypt(decode(template, ('base64')), encryptionkey_template_endpoint, 'compress-algo=1, cipher-algo=aes256') INTO current_endpoint_value
			from cognaio_design.app_templates_endpoint WHERE disabledat is null Order by createdat desc LIMIT 1;
		
		if current_endpoint_value is null then
			RAISE EXCEPTION 'Nonexistent endpoint template'
      			USING HINT = 'Please check your endpoint templates';
		end if;
		
		INSERT INTO cognaio_design.app_plans (
			name, description, fk_scope, type, maxitems, maxitems_type, maxitems_scope, public, admin_authorization_scopes, appkey_expiration_in_minutes, createdby
		) VALUES(existing_plan_name
			, existing_plan_description
			, existing_scope_parent_key
			, 'api'
			, existing_plan_maxItems
			, 'document'
			, existing_plan_maxItemsScope
			, false
			, '["scopes"]'
			, existing_plan_appkey_expiration_in_minutes
			, userkey
		) RETURNING key INTO key_out;

		CALL cognaio_design.crypto(
			'encrypt',
			current_endpoint_value,
			encryptionkey_endpoint,
			existing_scope_parent_key::text,
			current_endpoint_value
		);
		
		endpoint_name = current_scope_name || '-' || existing_plan_name || ' endpoints';
		
		INSERT INTO cognaio_design.def_process_endpoints(name, endpoints_def)
			VALUES (endpoint_name, current_endpoint_value)
			RETURNING key INTO endpoint_key;
		
		outbound_name = current_scope_name || '-' || existing_plan_name || ' outbound';			
		
		INSERT INTO cognaio_design.def_process_outbounds(name, outbound_def)
			VALUES (outbound_name, current_outbound_value)
			RETURNING key INTO outbound_key;
			
		mapping_name = current_scope_name || '-' || existing_plan_name || ' mapping';
			
		INSERT INTO cognaio_design.def_process_mappings(
			name, fk_scope, fk_plan, fk_endpoints_def, fk_outbound_def)
			VALUES (mapping_name, existing_scope_parent_key, key_out, endpoint_key, outbound_key);
	else
		UPDATE cognaio_design.app_plans
			SET name = CASE WHEN existing_plan_name is not null THEN existing_plan_name ELSE name END
			, description = CASE WHEN existing_plan_description is not null THEN existing_plan_description ELSE description END
			, maxitems = CASE WHEN existing_plan_maxItems is not null THEN existing_plan_maxItems ELSE maxitems END
			, maxitems_scope = CASE WHEN existing_plan_maxItemsScope is not null and existing_plan_maxItemsScope != maxitems_scope THEN existing_plan_maxItemsScope ELSE maxitems_scope END
			, appkey_expiration_in_minutes = CASE WHEN existing_plan_appkey_expiration_in_minutes is not null THEN existing_plan_appkey_expiration_in_minutes ELSE appkey_expiration_in_minutes END
			, modifiedat = timestamp_current
			, modifiedby = userkey
		WHERE key = existing_plan_key and fk_scope = existing_scope_parent_key and disabledat is null RETURNING key INTO key_out;
	end if;
END
$_$;


ALTER PROCEDURE cognaio_design.plan_createorupdate(IN plan_options json, IN userkey uuid, IN encryptionkey_template_endpoint text, IN encryptionkey_endpoint text, OUT key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 416 (class 1255 OID 27718)
-- Name: plan_delete(uuid, uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.plan_delete(IN plankey uuid, IN userkey uuid, OUT key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	endpoints_to_delete uuid[];
	outbounds_to_delete uuid[];
BEGIN
    timestamp_current = timezone('UTC', now());
	key_out = plankey;
		
	UPDATE cognaio_design.app_keys
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan = plankey and disabledat is null;
	
	endpoints_to_delete := ARRAY(SELECT fk_endpoints_def FROM cognaio_design.def_process_mappings		
		WHERE fk_plan = plankey and disabledat is null
	);
	
	outbounds_to_delete := ARRAY(SELECT fk_outbound_def FROM cognaio_design.def_process_mappings		
		WHERE fk_plan = plankey and disabledat is null
	);
	
	UPDATE cognaio_design.def_process_endpoints
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key = ANY(endpoints_to_delete) and disabledat is null;
	
	UPDATE cognaio_design.def_process_outbounds
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key = ANY(outbounds_to_delete) and disabledat is null;
	
	UPDATE cognaio_design.def_process_mappings
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan = plankey and disabledat is null;
		
	UPDATE cognaio_design.def_process_projects
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan = plankey and disabledat is null;
	
	UPDATE cognaio_design.app_plans
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key = plankey and disabledat is null;
END
$$;


ALTER PROCEDURE cognaio_design.plan_delete(IN plankey uuid, IN userkey uuid, OUT key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 417 (class 1255 OID 27719)
-- Name: scope_createorupdate(json, uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.scope_createorupdate(IN scope_options json, IN userkey uuid, OUT key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	existing_scope_key uuid;
	existing_organization_parent_key uuid;
	existing_scope_name text;
	existing_scope_description text;
BEGIN
    timestamp_current = timezone('UTC', now());
	existing_scope_key = (scope_options->>'key')::uuid;
	existing_organization_parent_key = (scope_options->>'parent')::uuid;
	existing_scope_name = (scope_options->>'name')::text;
	existing_scope_description = (scope_options->>'description')::text;
	
	if existing_scope_key is null then
		INSERT INTO cognaio_design.app_scopes (
			name, description, createdby
		) VALUES(existing_scope_name
			, existing_scope_description
			, userkey
		) RETURNING key INTO key_out;
		
		INSERT INTO cognaio_design.app_organization_scopes (
			fk_organization_key, fk_scope_key, createdby
		) VALUES(existing_organization_parent_key
			, key_out
			, userkey
		);
	else
		UPDATE cognaio_design.app_scopes
			SET name = CASE WHEN existing_scope_name is not null THEN existing_scope_name ELSE name END
			, description = CASE WHEN existing_scope_description is not null THEN existing_scope_description ELSE description END
			, modifiedat = timestamp_current
			, modifiedby = userkey
		WHERE key = existing_scope_key and disabledat is null RETURNING key INTO key_out;
	end if;
END
$$;


ALTER PROCEDURE cognaio_design.scope_createorupdate(IN scope_options json, IN userkey uuid, OUT key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 418 (class 1255 OID 27720)
-- Name: scope_delete(uuid, uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.scope_delete(IN scopekey uuid, IN userkey uuid, OUT key_out uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp_current timestamp;
	endpoints_to_delete uuid[];
	outbounds_to_delete uuid[];
BEGIN
    timestamp_current = timezone('UTC', now());
	key_out = scopekey;
		
	UPDATE cognaio_design.app_keys
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan in (
		SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
			SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
		)
	) and disabledat is null;
	
	endpoints_to_delete := ARRAY(SELECT fk_endpoints_def FROM cognaio_design.def_process_mappings		
		WHERE fk_plan in (
			SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
				SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
			)
		) and disabledat is null
	);
	
	outbounds_to_delete := ARRAY(SELECT fk_outbound_def FROM cognaio_design.def_process_mappings		
		WHERE fk_plan in (
			SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
				SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
			)
		) and disabledat is null
	);
	
	UPDATE cognaio_design.def_process_endpoints
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key = ANY(endpoints_to_delete) and disabledat is null;
	
	UPDATE cognaio_design.def_process_outbounds
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key = ANY(outbounds_to_delete) and disabledat is null;
	
	UPDATE cognaio_design.def_process_mappings
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan in (
		SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
			SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
		)
	) and disabledat is null;
		
	UPDATE cognaio_design.def_process_projects
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_plan in (
		SELECT key FROM cognaio_design.app_plans WHERE fk_scope in (
			SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
		)
	) and disabledat is null;
	
	UPDATE cognaio_design.app_plans
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE fk_scope in (
		SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
	) and disabledat is null;
	
	UPDATE cognaio_design.app_scopes
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key in (
		SELECT fk_scope_key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
	) and disabledat is null;
	
	UPDATE cognaio_design.app_organization_scopes
		SET disabledat = timestamp_current
		, disabledby = userkey
	WHERE key in (
		SELECT key FROM cognaio_design.app_organization_scopes WHERE fk_scope_key = scopekey AND disabledat is null
	) and disabledat is null;
END
$$;


ALTER PROCEDURE cognaio_design.scope_delete(IN scopekey uuid, IN userkey uuid, OUT key_out uuid) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 419 (class 1255 OID 27721)
-- Name: unlock_mailboxes_expired(uuid); Type: PROCEDURE; Schema: cognaio_design; Owner: postgres
--

CREATE PROCEDURE cognaio_design.unlock_mailboxes_expired(IN plankey uuid, OUT affectedboxes integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
	boxes_lock_expired uuid; 
BEGIN
    affectedBoxes := 0;
	
	UPDATE cognaio_design.def_process_mailboxes updateboxes
		SET lock_token = null, 
		lockedat = null, 
		lockedby_user = null, 
		lockedby_boxmapping = null,
		lock_expiresat = null
		FROM cognaio_design.def_process_mailbox_mappings map
			INNER JOIN cognaio_design.def_process_mailboxes box ON map.fk_mailbox = box.key And box.disabledat IS NULL
			And box.lock_expiresat IS NOT NULL AND box.lock_expiresat < timezone('UTC', now())
			AND map.fk_plan = plankey AND map.disabledat IS NULL
		WHERE updateboxes.key = box.key;
		
	GET DIAGNOSTICS affectedBoxes = ROW_COUNT;
	RAISE NOTICE 'unlock_mailboxes_expired() affectedBoxes: %', affectedBoxes;
END
$$;


ALTER PROCEDURE cognaio_design.unlock_mailboxes_expired(IN plankey uuid, OUT affectedboxes integer) OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 226 (class 1259 OID 27722)
-- Name: app_content_filter_triggers; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_content_filter_triggers (
    filter_trigger_expression text NOT NULL,
    filter_trigger_replacement text DEFAULT ''::text,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone
);


ALTER TABLE cognaio_design.app_content_filter_triggers OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 272 (class 1259 OID 64087)
-- Name: app_essentials; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_essentials (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    kind integer NOT NULL,
    token text NOT NULL,
    metadata text DEFAULT '{}'::text,
    signature text,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    createdby uuid,
    modifiedat timestamp without time zone,
    modifiedby uuid
);


ALTER TABLE cognaio_design.app_essentials OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 227 (class 1259 OID 27729)
-- Name: app_keys; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_keys (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    description character varying(255),
    descriptor_description character varying(150),
    fk_plan uuid NOT NULL,
    fk_user uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    expiresat timestamp without time zone NOT NULL,
    fk_organization uuid,
    disabledby uuid,
    next_expiration_alert_notifaction_send_at timestamp without time zone
);


ALTER TABLE cognaio_design.app_keys OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 228 (class 1259 OID 27734)
-- Name: app_notification_templates; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_notification_templates (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    language text NOT NULL,
    subject text NOT NULL,
    html text NOT NULL
);


ALTER TABLE cognaio_design.app_notification_templates OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 229 (class 1259 OID 27740)
-- Name: app_notifications; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_notifications (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    addresses json DEFAULT '{   "to": [],   "cc": [],   "bcc": [] }'::json
);


ALTER TABLE cognaio_design.app_notifications OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 230 (class 1259 OID 27747)
-- Name: app_organization_scopes; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_organization_scopes (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_organization_key uuid NOT NULL,
    fk_scope_key uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.app_organization_scopes OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 231 (class 1259 OID 27752)
-- Name: app_organization_users; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_organization_users (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_organization_key uuid NOT NULL,
    fk_user_key uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedat timestamp without time zone,
    modifiedby uuid,
    user_permissions json DEFAULT '{}'::json
);


ALTER TABLE cognaio_design.app_organization_users OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 232 (class 1259 OID 27760)
-- Name: app_organizations; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_organizations (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_parent_organization uuid,
    name character varying(150) NOT NULL,
    descriptor_name character varying(150),
    description character varying(255),
    descriptor_description character varying(150),
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    paymentdetails text DEFAULT 'this is just a placeholder for now'::text NOT NULL,
    logo_base64 text,
    email text,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone,
    theme json
);


ALTER TABLE cognaio_design.app_organizations OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 233 (class 1259 OID 27768)
-- Name: app_plans; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_plans (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(255),
    name_description character varying(150),
    description character varying(255),
    descriptor_description character varying(150),
    fk_scope uuid NOT NULL,
    type cognaio_design.plan_type NOT NULL,
    maxitems integer DEFAULT 0 NOT NULL,
    maxitems_type cognaio_design.plan_limitation_type DEFAULT 'document'::cognaio_design.plan_limitation_type NOT NULL,
    maxitems_scope cognaio_design.plan_limitation_scope DEFAULT 'day'::cognaio_design.plan_limitation_scope NOT NULL,
    billable boolean DEFAULT true,
    public boolean DEFAULT false,
    appkey_expiration_in_minutes bigint DEFAULT 60 NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    admin_authorization_scopes json DEFAULT '[]'::json,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.app_plans OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 234 (class 1259 OID 27782)
-- Name: app_registered_users; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_registered_users (
    fk_user_key uuid NOT NULL,
    otp_token text,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    disabledat timestamp without time zone,
    createdby uuid,
    modifiedby uuid,
    disabledby uuid
);


ALTER TABLE cognaio_design.app_registered_users OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 235 (class 1259 OID 27788)
-- Name: app_registration_requests; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_registration_requests (
    key uuid NOT NULL,
    fk_organization uuid NOT NULL,
    email text NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    createdby uuid,
    registeredat timestamp without time zone,
    registeredby uuid,
    disabledat timestamp without time zone,
    disabledby uuid,
    expiresat timestamp without time zone
);


ALTER TABLE cognaio_design.app_registration_requests OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 236 (class 1259 OID 27794)
-- Name: app_scopes; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_scopes (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    descriptor_name character varying(150),
    description character varying(255),
    descriptor_description character varying(150),
    public boolean DEFAULT false,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.app_scopes OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 237 (class 1259 OID 27802)
-- Name: app_templates_endpoint; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_templates_endpoint (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    template text NOT NULL
);


ALTER TABLE cognaio_design.app_templates_endpoint OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 238 (class 1259 OID 27809)
-- Name: app_templates_outbound; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_templates_outbound (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    outbound json NOT NULL
);


ALTER TABLE cognaio_design.app_templates_outbound OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 239 (class 1259 OID 27816)
-- Name: app_users; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.app_users (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    email text NOT NULL,
    description character varying(255),
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.app_users OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 240 (class 1259 OID 27823)
-- Name: def_process_endpoints; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_endpoints (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    description character varying(255),
    endpoints_def text NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.def_process_endpoints OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 241 (class 1259 OID 27830)
-- Name: def_process_mailbox_mappings; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_mailbox_mappings (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    fk_mailbox uuid NOT NULL,
    fk_plan uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone
);


ALTER TABLE cognaio_design.def_process_mailbox_mappings OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 242 (class 1259 OID 27835)
-- Name: def_process_mailboxes; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_mailboxes (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    description character varying(255),
    lockedat timestamp without time zone,
    lock_token text,
    lockedby_user uuid,
    lockedby_boxmapping uuid,
    lock_expiresat timestamp without time zone,
    mailbox_def text,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone
);


ALTER TABLE cognaio_design.def_process_mailboxes OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 243 (class 1259 OID 27842)
-- Name: def_process_mappings; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_mappings (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    description character varying(255),
    fk_scope uuid,
    fk_plan uuid,
    fk_endpoints_def uuid NOT NULL,
    fk_outbound_def uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    fk_response_transformation uuid,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    modifiedat timestamp without time zone
);


ALTER TABLE cognaio_design.def_process_mappings OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 244 (class 1259 OID 27847)
-- Name: def_process_outbounds; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_outbounds (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    description character varying(255),
    outbound_def json,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    disabledat timestamp without time zone,
    modifiedat timestamp without time zone,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid
);


ALTER TABLE cognaio_design.def_process_outbounds OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 245 (class 1259 OID 27854)
-- Name: def_process_projects; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_projects (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(150) NOT NULL,
    description character varying(255),
    fk_plan uuid NOT NULL,
    createdat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone,
    disabledat timestamp without time zone,
    outbound_def json DEFAULT '{}'::json NOT NULL,
    fk_response_transformation uuid,
    createdby uuid,
    disabledby uuid,
    modifiedby uuid,
    is_selectable_wo_designer boolean DEFAULT true
);


ALTER TABLE cognaio_design.def_process_projects OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 246 (class 1259 OID 27863)
-- Name: def_process_response_transformations; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.def_process_response_transformations (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    transformation_def text,
    disabledat timestamp without time zone,
    createat timestamp without time zone DEFAULT timezone('UTC'::text, now()),
    modifiedat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_design.def_process_response_transformations OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 247 (class 1259 OID 27871)
-- Name: loc_languages; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.loc_languages (
    language character varying(10) NOT NULL,
    description character varying(150)
);


ALTER TABLE cognaio_design.loc_languages OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 248 (class 1259 OID 27874)
-- Name: loc_translations; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.loc_translations (
    descriptor character varying(150) NOT NULL,
    fk_language character varying(10) NOT NULL,
    translation character varying(255)
);


ALTER TABLE cognaio_design.loc_translations OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 249 (class 1259 OID 27877)
-- Name: schema_versions; Type: TABLE; Schema: cognaio_design; Owner: postgres
--

CREATE TABLE cognaio_design.schema_versions (
    key uuid DEFAULT gen_random_uuid() NOT NULL,
    version text NOT NULL,
    description text,
    appliedat timestamp without time zone DEFAULT timezone('UTC'::text, now())
);


ALTER TABLE cognaio_design.schema_versions OWNER TO {{ .Values.cognaioservice.env.db.postgreSqlUser }};

--
-- TOC entry 3903 (class 0 OID 27722)
-- Dependencies: 226
-- Data for Name: app_content_filter_triggers; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.app_content_filter_triggers VALUES ('/\bmuff/gi', '', '2023-10-10 10:41:08.647722', '2023-10-10 10:41:08.647722');
INSERT INTO cognaio_design.app_content_filter_triggers VALUES ('/\bgringo/gi', '', '2023-09-14 15:20:23.356146', '2023-09-14 15:20:23.356146');
INSERT INTO cognaio_design.app_content_filter_triggers VALUES ('/\bnigg/gi', '', '2023-09-14 15:20:52.944251', '2023-09-14 15:20:23.356146');
INSERT INTO cognaio_design.app_content_filter_triggers VALUES ('/\bwigger/gi', '', '2023-09-14 15:20:36.202133', '2023-09-14 15:20:23.356146');

--
-- TOC entry 3905 (class 0 OID 27734)
-- Dependencies: 228
-- Data for Name: app_notification_templates; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.app_notification_templates VALUES ('d3ebd986-74d0-11ee-b962-0242ac120002', 'OtpNotification', 'de', 'One time passwort für ''My cognaio'' der DTI Cognaio services', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Willkommen zu DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $emailAddress,</strong><strong> </strong><br><br><strong>Sie
                                              haben ein One-Time-Passwort angefordert.</strong><strong>
                                            </strong><br><br><strong>Über folgenden Link können Sie sich über das
                                              One-Time-Passwort einloggen:</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>One-Time-Passwort:
                                              $password</strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>Dieses Passwort wird ablaufen am:
                                              $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('cd5c1978-74d0-11ee-b962-0242ac120002', 'OtpNotification', 'en', 'One time passwort für ''My cognaio'' der DTI Cognaio services', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Welcome to DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $emailAddress,</strong><strong> </strong><br><br><strong>You
                                              have requested a one time password to enter your private cognaio team
                                              services.</strong><strong> </strong><br><br><strong>Please follow the link
                                              below with your one time password:</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>One-Time-Passwort:
                                              $password</strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>This password will expire at: $expiresat GMT+0000</strong>
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Enjoy,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('c25623b6-74d0-11ee-b962-0242ac120002', 'RegisterRequestNotification', 'en', 'Your invitation to ''My cognaio'' at DTI Cognaio services', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Welcome to DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $emailAddress,</strong><strong> </strong><br><br><strong>Your
                                              teammate $registeredInviterUserEmail invited you to join the ''My cognaio''
                                              team.`</strong><strong> </strong><br><br><strong>By following the link
                                              below, you are registering to your private cognaio team
                                              services:</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Register
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Organization:
                                              $organization</strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>This link will expire at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Enjoy,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('19a8e524-76ff-11ee-b962-0242ac120002', 'ResubscribeAppKeyRequestForwardNotification', 'en', 'A resend of the app key for $scope was requested', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Notification from DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $forwardToThisUser,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer has requested a resend of the
                                              current app key.</strong><strong> <br><br><strong>Find the button to log in, as
                                                well as your current app key below:</strong><strong> </strong>
                                              </div>
                                              <div
                                              style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                              <br><br><strong>$appkey</strong></div>
                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">
                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>Expires
                                              at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('d041b910-76fe-11ee-b962-0242ac120002', 'ResubscribeAppKeyRequestForwardNotification', 'de', 'App-Key für $scope wurde neu angefordert', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Benachrichtigung der DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $forwardToThisUser,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer hat den aktuellen
                                              App-Key neu angefordert</strong><strong> <br><br><strong>Anbei der Log in 
                                                Button, sowie Ihr aktueller App-Key:</strong><strong> </strong>
                                              </div>
                                              <div
                                              style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                              <br><br><strong>$appkey</strong></div>
                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">
                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>Ablaufdatum: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('a831650d-c29e-4bc5-a2bc-b0482d4429fb', 'RepositoryUpload', 'de', 'Ein Repository für $organization-$plan wurde hochgeladen', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
        <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
                <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                    <div
                        style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--email-header">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td
                                                    style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                cellspacing="0" cellpadding="0" border="0">
                                                                <tbody>
                                                                    <tr>
                                                                        <td style="width:140px">
                                                                            <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                            href="https://dti.group/">
                                                                            <img width="140"
                                                                            style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                            src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                            height="auto">
                                                                            </a>
                                                                        </td>
                                                                    </tr>
                                                                </tbody>
                                                                </table>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--block c--block-text">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                align="left">
                                                                <div
                                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                <strong>Benachrichtigung der DTI Cognaio services
                                                                $baseWebAppLink</strong><strong> </strong>
                                                                </div>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--block c--block-text">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                align="left">
                                                                <div
                                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                <strong>Hallo,</strong>
                                                                <br><br><strong>ein Repository ''$repositoryName'' wurde hochgeladen am $date GMT+0000.</strong>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                        </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                        </div>
                        <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                                <tr>
                                    <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                                <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                        border="0">
                                                        <tbody>
                                                            <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                align="left">
                                                                <div
                                                                    style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    <strong>Hochgeladen von: $emailIssuer</strong>
                                                                    <br><strong>Organization: $organization</strong>
                                                                    <br><strong>Scope: $scope</strong>
                                                                    <br><strong>Plan: $plan</strong>
                                                                    <br><strong>Repository-Id: $repositoryId</strong>
                                                                    <br><strong>Repository-Typ: $repositoryType</strong>
                                                                    <br><strong>Index-Typ: $repositoryIndexType</strong>
                                                                </td>
                                                            </tr>
                                                        </tbody>
                                                    </table>
                                                    </td>
                                                </tr>
                                            </tbody>
                                        </table>
                                        </div>
                                    </td>
                                </tr>
                            </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Viele Grüsse,<br><strong>Das Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                </td>
                </tr>
            </tbody>
        </table>
        </div>
        </div>
    </body>
    </html>');

INSERT INTO cognaio_design.app_notification_templates VALUES ('2458b2be-3fa0-431c-8134-920009fdd724', 'RepositoryUpload', 'en', 'A repository for $organization-$plan was uploaded', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
        <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
                <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                    <div
                        style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--email-header">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td
                                                    style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                cellspacing="0" cellpadding="0" border="0">
                                                                <tbody>
                                                                    <tr>
                                                                        <td style="width:140px">
                                                                            <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                            href="https://dti.group/">
                                                                            <img width="140"
                                                                            style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                            src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                            height="auto">
                                                                            </a>
                                                                        </td>
                                                                    </tr>
                                                                </tbody>
                                                                </table>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--block c--block-text">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                align="left">
                                                                <div
                                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                <strong>Notification DTI Cognaio services $baseWebAppLink</strong><strong> </strong>
                                                                </div>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                    </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                    </div>
                    <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                        class="c--block c--block-text">
                        <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                            <tr>
                                <td
                                    style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                    <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                        <tbody>
                                            <tr>
                                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                    border="0">
                                                    <tbody>
                                                        <tr>
                                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                align="left">
                                                                <div
                                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                <strong>Hello,</strong>
                                                                <br><br><strong>a Repository ''$repositoryName'' was uploaded at $date GMT+0000.</strong>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                    </table>
                                                </td>
                                            </tr>
                                        </tbody>
                                        </table>
                                        </div>
                                </td>
                            </tr>
                            </tbody>
                        </table>
                        </div>
                        <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                            cellspacing="0" cellpadding="0" border="0" align="center">
                            <tbody>
                                <tr>
                                    <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                        style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                        class="mj-column-per-100 outlook-group-fix">
                                        <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                                <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                    <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                        border="0">
                                                        <tbody>
                                                            <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                align="left">
                                                                <div
                                                                    style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    <strong>Uploaded by: $emailIssuer</strong>
                                                                    <br><strong>Organization: $organization</strong>
                                                                    <br><strong>Scope: $scope</strong>
                                                                    <br><strong>Plan: $plan</strong>
                                                                    <br><strong>Repository-Id: $repositoryId</strong>
                                                                    <br><strong>Repository-Type: $repositoryType</strong>
                                                                    <br><strong>Index-Type: $repositoryIndexType</strong>
                                                                </td>
                                                            </tr>
                                                        </tbody>
                                                    </table>
                                                    </td>
                                                </tr>
                                            </tbody>
                                        </table>
                                        </div>
                                    </td>
                                </tr>
                            </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Cheers,<br><strong>The Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                </td>
                </tr>
            </tbody>
        </table>
        </div>
        </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('e63dfd56-7707-11ee-b962-0242ac120002', 'SubscribeAppKeyRequestForwardNotification', 'de', 'Es wurde ein App-Key für $scope angefordert', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Benachrichtigung der DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $forwardToThisUser,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer hat einen Extraction App-Key
                                              angefordert`</strong><strong> </strong><br><br><strong>Anbei der Log in 
                                              Button, sowie Ihren App-Key:</strong><strong>
                                            </strong></div>
                                            <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                            <br><br><strong>$appkey</strong></div>
                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>Ablaufdatum: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('7fb526de-7704-11ee-b962-0242ac120002', 'SubscribeAppKeyRequestNotification', 'de', 'Ihr App-Key für $scope', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Willkommen zu DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $emailAddress,</strong><strong> </strong><br><br><strong>Wir
                                              begrüßen Sie bei DTI Cognaio services.</strong><strong>
                                            </strong><br><br><strong>Anbei der Log in  Button, sowie Ihren App-Key
                                              anbei:</strong><strong> </strong></div>
                                            <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                            <br><br><strong>$appkey</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>Ablaufdatum: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('8c455dc4-7704-11ee-b962-0242ac120002', 'SubscribeAppKeyRequestNotification', 'en', 'Your App-Key for $scope', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Welcome to DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $emailAddress,</strong><strong>
                                            </strong><br><br><strong>Thanks for joining DTI Cognaio services.</strong><strong>
                                            </strong><br><br><strong>Find the button to log in, as well as your app key
                                              below:</strong><strong> </strong></div>
                                            <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                            <br><br><strong>$appkey</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>Expires
                                              at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('a96cce94-76f2-11ee-b962-0242ac120002', 'UnsubscribeAppKeyRequestForwardNotification', 'en', 'An unsubscription of app key for $scope was requested', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Notification from DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $emailAddress,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer has requested an unsubscription
                                              of an app key.`</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>The
                                              unsubscription link will expire at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('5c809300-76fb-11ee-b962-0242ac120002', 'ResubscribeAppKeyRequestNotification', 'en', 'Your app key for $scope', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Welcome back to DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $emailAddress,</strong><strong> </strong><br><br><strong>You
                                              have requested a resend of your current app key.</strong><strong>
                                              <br><br><strong>Find the button to log in, as well as your current app key
                                                below:</strong><strong> </strong>
                                              </div>
                                              <div
                                              style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                              <br><br><strong>$appkey</strong></div>
                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">
                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>Expires
                                              at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('30cf62d6-76fb-11ee-b962-0242ac120002', 'ResubscribeAppKeyRequestNotification', 'de', 'Ihr App-Key für $scope', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Willkommen zurück zu DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $emailAddress,</strong><strong> </strong><br><br><strong>Sie
                                              haben Ihr aktueller App-Key erneut
                                              angefordert.</strong><br><br><strong>Anbei der Log in  Button, sowie Ihren
                                              aktuellen App-Key:</strong></div>
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                            <br><br><strong>$appkey</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">
                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong>
                                            </strong><br><br><strong>Ablaufdatum: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('0f16c816-7708-11ee-b962-0242ac120002', 'SubscribeAppKeyRequestForwardNotification', 'en', 'An app key request for $scope was send', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Notification from DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello $forwardToThisUser,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer requested an app
                                              key</strong><strong> </strong><br><br><strong>Find the button to log in, as well
                                              as your current app key below:</strong><strong>
                                            </strong></div>
                                            <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c;width:500px">
                                            <br><br><strong>$appkey</strong></div>
                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">

                                          <table style="border-collapse:separate;line-height:100%" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td valign="middle"
                                                  style="border:none;border-radius:4px;background:#585986"
                                                  role="presentation" bgcolor="#585986" align="center">
                                                  <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                    href="$buttonUrl">
                                                    Log In
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>Expires
                                              at: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('729b1f2e-76f2-11ee-b962-0242ac120002', 'UnsubscribeAppKeyRequestForwardNotification', 'de', 'Abmeldung des app keys für $scope angeordert', '<html>

<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>

  </title>





  <style type="text/css">
    #outlook a {
      padding: 0;
    }

    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }

    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }

    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }

    p {
      display: block;
      margin: 13px 0;
    }
  </style>




  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>


  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }

      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>


</head>

<body style="background-color:#f5f5f5">



  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">





    <div style="margin:0px auto;max-width:582px">

      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">



              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">

                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">

                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">

                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">

                                                  </a>

                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>Benachrichtigung der DTI Cognaio services
                                              $baseWebAppLink</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo $emailAddress,</strong><strong>
                                            </strong><br><br><strong>$emailAddressIssuer hat eine Abmeldung des app keys
                                              angeordert.`</strong><strong> </strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-action">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                          align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">


                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <br><br><strong>Scope: $scope</strong><strong>
                                            </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                            </strong><br><br><strong></strong><strong> </strong><br><br><strong>Dieser
                                              Link wird ablaufen am: $expiresat GMT+0000</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">

                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">




                                          <div style="height:20px">
                                            &nbsp;
                                          </div>




                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>





              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">

                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">


                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">

                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">

                                  <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">

                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">

                                        </td>
                                      </tr>

                                    </tbody>
                                  </table>

                                </td>
                              </tr>
                            </tbody>
                          </table>

                        </div>


                      </td>
                    </tr>
                  </tbody>
                </table>

              </div>



            </td>
          </tr>
        </tbody>
      </table>

    </div>





  </div>



</body>

</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('7de7260c-a3fe-4dc9-a70f-1f3eb41b5b5f', 'AppKeyCloseToExpireNotification', 'en', 'App-Key for ''$plan'' will expire soon', '<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>
  </title>
  <style type="text/css">
    #outlook a {
      padding: 0;
    }
    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }
    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }
    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }
    p {
      display: block;
      margin: 13px 0;
    }
  </style>
  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>
  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }
      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>
</head>
<body style="background-color:#f5f5f5">
  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
    <div style="margin:0px auto;max-width:582px">
      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">
                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">
                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello team,</strong><strong>
                                            </strong><br><br><strong>The App-Key will expire soon at: $expiresat GMT+0000</strong><strong><strong>
                                            </strong><br><br><strong>Please consider to renew the App-Key in time.</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Organization:
                                              $organization</strong><br><br>
                                            <strong>Scope:
                                              $scope</strong><br><br>
                                            <strong>Plan:
                                              $plan</strong>
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">
                                          <div style="height:20px">
                                            &nbsp;
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('6581817b-8d4e-402a-94c6-922d57d691a6', 'AppKeyCloseToExpireNotification', 'de', 'App-Key für ''$plan'' wird bald ablaufen', '<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>
  </title>
  <style type="text/css">
    #outlook a {
      padding: 0;
    }
    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }
    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }
    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }
    p {
      display: block;
      margin: 13px 0;
    }
  </style>
  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>
  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }
      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>
</head>
<body style="background-color:#f5f5f5">
  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
    <div style="margin:0px auto;max-width:582px">
      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">
                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">
                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo Team,</strong><strong>
                                            </strong><br><br><strong>Der App-Key wird ablaufen am: $expiresat GMT+0000</strong><strong><strong>
                                            </strong><br><br><strong>Bitte erneuern Sie Ihren App-Key innerhalb der nächsten Tage.</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Organisation:
                                              $organization</strong><br><br>
                                            <strong>Scope:
                                              $scope</strong><br><br>
                                            <strong>Plan:
                                              $plan</strong>
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">
                                          <div style="height:20px">
                                            &nbsp;
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('4beb0d60-36a5-4e39-8826-50d389b5a22d', 'RegisterRequestCommitNotification', 'en', '$invitedUserEmail has joined the ''My coganio'' Team of organization ''$organization''', '<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>
  </title>
  <style type="text/css">
    #outlook a {
      padding: 0;
    }
    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }
    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }
    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }
    p {
      display: block;
      margin: 13px 0;
    }
  </style>
  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>
  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }
      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>
</head>
<body style="background-color:#f5f5f5">
  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
    <div style="margin:0px auto;max-width:582px">
      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">
                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">
                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hello team,</strong><strong>
                                            </strong><br><br><strong>$invitedUserEmail has joined the team at: $comittat GMT+0000</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Organization:
                                              $organization</strong>
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Cheers,<br><strong>The Cognaio Team</strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">
                                          <div style="height:20px">
                                            &nbsp;
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('da06eeaa-3f1d-4a41-9659-c32f4caff10a', 'RegisterRequestCommitNotification', 'de', '$invitedUserEmail ist dem ''My coganio'' Team der Organisation ''$organization'' beigetreten', '<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>
  </title>
  <style type="text/css">
    #outlook a {
      padding: 0;
    }
    body {
      margin: 0;
      padding: 0;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
    }
    table,
    td {
      border-collapse: collapse;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }
    img {
      border: 0;
      height: auto;
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
    }
    p {
      display: block;
      margin: 13px 0;
    }
  </style>
  <style type="text/css">
    @media only screen and (min-width:480px) {
      .mj-column-per-100 {
        width: 100% !important;
        max-width: 100%;
      }
    }
  </style>
  <style type="text/css">
    @media only screen and (max-width:480px) {
      table.full-width-mobile {
        width: 100% !important;
      }
      td.full-width-mobile {
        width: auto !important;
      }
    }
  </style>
</head>
<body style="background-color:#f5f5f5">
  <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
    <div style="margin:0px auto;max-width:582px">
      <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
        <tbody>
          <tr>
            <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
              <div
                style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-header">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td
                                  style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                          <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                            cellspacing="0" cellpadding="0" border="0">
                                            <tbody>
                                              <tr>
                                                <td style="width:140px">
                                                  <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                    href="https://dti.group/">
                                                    <img width="140"
                                                      style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                      src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                      height="auto">
                                                  </a>
                                                </td>
                                              </tr>
                                            </tbody>
                                          </table>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                            <strong>DTI Cognaio services $baseWebAppLink</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Hallo Team,</strong><strong>
                                            </strong><br><br><strong>$invitedUserEmail ist Ihrem Team beigetreten am: $comittat GMT+0000</strong><strong>
                                            </strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="left">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            <strong>Organisation:
                                              $organization</strong>
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--block c--block-text">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                          align="left">
                                          <div
                                            style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            Auf bald,<br><strong>Das Cognaio Team</strong></div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;word-break:break-word">
                                          <div style="height:20px">
                                            &nbsp;
                                          </div>
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div
                style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                class="c--email-footer c--courier-footer">
                <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                  cellspacing="0" cellpadding="0" border="0" align="center">
                  <tbody>
                    <tr>
                      <td
                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                        <div
                          style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                          class="mj-column-per-100 outlook-group-fix">
                          <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                            <tbody>
                              <tr>
                                <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                  <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                    border="0">
                                    <tbody>
                                      <tr>
                                        <td style="font-size:0px;padding:0px;word-break:break-word"
                                          class="c--text-subtext" align="center">
                                        </td>
                                      </tr>
                                    </tbody>
                                  </table>
                                </td>
                              </tr>
                            </tbody>
                          </table>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('d770cfbc-74d0-11ee-b962-0242ac120002', 'RegisterRequestNotification', 'de', 'Ihre Einladung zu ''My cognaio'' der DTI Cognaio services', '<html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <title>
      </title>
      <style type="text/css">
        #outlook a {
          padding: 0;
        }
        body {
          margin: 0;
          padding: 0;
          -webkit-text-size-adjust: 100%;
          -ms-text-size-adjust: 100%;
        }
        table,
        td {
          border-collapse: collapse;
          mso-table-lspace: 0pt;
          mso-table-rspace: 0pt;
        }
        img {
          border: 0;
          height: auto;
          line-height: 100%;
          outline: none;
          text-decoration: none;
          -ms-interpolation-mode: bicubic;
        }
        p {
          display: block;
          margin: 13px 0;
        }
      </style>
      <style type="text/css">
        @media only screen and (min-width:480px) {
          .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
          }
        }
      </style>
      <style type="text/css">
        @media only screen and (max-width:480px) {
          table.full-width-mobile {
            width: 100% !important;
          }
          td.full-width-mobile {
            width: auto !important;
          }
        }
      </style>
    </head>
    <body style="background-color:#f5f5f5">
      <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
          <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
              <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                  <div
                    style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-header">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td
                                      style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                              <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td style="width:140px">
                                                      <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                        href="https://dti.group/">
                                                        <img width="140"
                                                          style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                          src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                          height="auto">
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                <strong>Willkommen zu DTI Cognaio services $baseWebAppLink</strong><strong>
                                                </strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Hallo $emailAddress,</strong><strong>
                                                </strong><br><br><strong>$registeredInviterUserEmail hat Sie ins Team ''My
                                                  cognaio'' eingeladen.`</strong><strong> </strong><br><br><strong>Über
                                                  folgenden Link können Sie Ihre Anmeldung bestätigen</strong><strong>
                                                </strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-action">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                              align="left">
                                              <table style="border-collapse:separate;line-height:100%" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td valign="middle"
                                                      style="border:none;border-radius:4px;background:#585986"
                                                      role="presentation" bgcolor="#585986" align="center">
                                                      <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                        href="$buttonUrl">
                                                        Registrieren
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="left">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Organisation:
                                                  $organization</strong><br><br><strong></strong><strong>
                                                </strong><br><br><strong>Dieser Link wird ablaufen am: $expiresat GMT+0000</strong>
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                Auf bald,<br><strong>Das Cognaio Team</strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;word-break:break-word">
                                              <div style="height:20px">
                                                &nbsp;
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div
                    style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer c--courier-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                      <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="center">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('0170d2f6-76f9-11ee-b962-0242ac120002', 'UnsubscribeAppKeyRequestNotification', 'en', 'Your unsubscription from DTI Cognaio services $scope', '<html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <title>
      </title>
      <style type="text/css">
        #outlook a {
          padding: 0;
        }
        body {
          margin: 0;
          padding: 0;
          -webkit-text-size-adjust: 100%;
          -ms-text-size-adjust: 100%;
        }
        table,
        td {
          border-collapse: collapse;
          mso-table-lspace: 0pt;
          mso-table-rspace: 0pt;
        }
        img {
          border: 0;
          height: auto;
          line-height: 100%;
          outline: none;
          text-decoration: none;
          -ms-interpolation-mode: bicubic;
        }
        p {
          display: block;
          margin: 13px 0;
        }
      </style>
      <style type="text/css">
        @media only screen and (min-width:480px) {
          .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
          }
        }
      </style>
      <style type="text/css">
        @media only screen and (max-width:480px) {
          table.full-width-mobile {
            width: 100% !important;
          }
          td.full-width-mobile {
            width: auto !important;
          }
        }
      </style>
    </head>
    <body style="background-color:#f5f5f5">
      <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
          <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
              <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                  <div
                    style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-header">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td
                                      style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                              <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td style="width:140px">
                                                      <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                        href="https://dti.group/">
                                                        <img width="140"
                                                          style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                          src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                          height="auto">
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                <strong>We are sorry to see you leaving...</strong><strong> </strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Hello $emailAddress,</strong><strong> </strong><br><br><strong>By
                                                  following the link below, you are confirming to unsubscribe
                                                  from App-Key created at: $appkey_createdat GMT+0000</strong><strong> </strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-action">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                              align="left">
                                              <table style="border-collapse:separate;line-height:100%" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td valign="middle"
                                                      style="border:none;border-radius:4px;background:#585986"
                                                      role="presentation" bgcolor="#585986" align="center">
                                                      <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                        href="$buttonUrl">
                                                        Unsubscribe
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="left">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <br><br><strong>Scope: $scope</strong><strong>
                                                </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                                </strong><br><br><strong></strong><strong> </strong><br><br><strong>This
                                                  link will expire at: $expiresat GMT+0000</strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                Goodbye,<br><strong>The Cognaio Team</strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;word-break:break-word">
                                              <div style="height:20px">
                                                &nbsp;
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div
                    style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer c--courier-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="center">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('dc4590c0-76f8-11ee-b962-0242ac120002', 'UnsubscribeAppKeyRequestNotification', 'de', 'Ihre Abmeldung der DTI Cognaio services $scope', '<html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <title>
      </title>
      <style type="text/css">
        #outlook a {
          padding: 0;
        }
        body {
          margin: 0;
          padding: 0;
          -webkit-text-size-adjust: 100%;
          -ms-text-size-adjust: 100%;
        }
        table,
        td {
          border-collapse: collapse;
          mso-table-lspace: 0pt;
          mso-table-rspace: 0pt;
        }
        img {
          border: 0;
          height: auto;
          line-height: 100%;
          outline: none;
          text-decoration: none;
          -ms-interpolation-mode: bicubic;
        }
        p {
          display: block;
          margin: 13px 0;
        }
      </style>
      <style type="text/css">
        @media only screen and (min-width:480px) {
          .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
          }
        }
      </style>
      <style type="text/css">
        @media only screen and (max-width:480px) {
          table.full-width-mobile {
            width: 100% !important;
          }
          td.full-width-mobile {
            width: auto !important;
          }
        }
      </style>
    </head>
    <body style="background-color:#f5f5f5">
      <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
          <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
              <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                  <div
                    style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-header">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td
                                      style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                              <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td style="width:140px">
                                                      <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                        href="https://dti.group/">
                                                        <img width="140"
                                                          style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                          src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                          height="auto">
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                <strong>Schade, daß Sie uns verlassen...</strong><strong> </strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Hallo $emailAddress,</strong><strong> </strong><br><br><strong>Über
                                                  folgenden Link bestätigen Sie die Abmeldung des App-Keys erstellt am: $appkey_createdat GMT+0000</strong><strong> </strong>
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-action">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:8px 0px;word-break:break-word" class="primary"
                                              align="left">
                                              <table style="border-collapse:separate;line-height:100%" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                  <tr>
                                                    <td valign="middle"
                                                      style="border:none;border-radius:4px;background:#585986"
                                                      role="presentation" bgcolor="#585986" align="center">
                                                      <a style="display:inline-block;background:#585986;color:#ffffff;font-family:Helvetica,Arial,sans-serif;font-size:14px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 20px;border-radius:4px"
                                                        href="$buttonUrl">
                                                        Abmelden
                                                      </a>
                                                    </td>
                                                  </tr>
                                                </tbody>
                                              </table>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="left">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <br><br><strong>Scope: $scope</strong><strong>
                                                </strong></strong><br><br><strong>Plan: $plan</strong><strong>
                                                </strong><br><br><strong></strong><strong> </strong><br><br><strong>Dieser
                                                  Link wird ablaufen am: $expiresat GMT+0000</strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                              align="left">
                                              <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                Auf bald,<br><strong>Das Cognaio Team</strong></div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;word-break:break-word">
                                              <div style="height:20px">
                                                &nbsp;
                                              </div>
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                  <div
                    style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer c--courier-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                      cellspacing="0" cellpadding="0" border="0" align="center">
                      <tbody>
                        <tr>
                          <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                            <div
                              style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                              class="mj-column-per-100 outlook-group-fix">
                              <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                  <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                      <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                          <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                              class="c--text-subtext" align="center">
                                            </td>
                                          </tr>
                                        </tbody>
                                      </table>
                                    </td>
                                  </tr>
                                </tbody>
                              </table>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('dc706518-d9f3-492d-b6d7-fd6191b3ccab', 'AppEssentialCloseToExpireNotification', 'de', 'Platform Lizenz ''$licenseKey'' wird bald ablaufen', '<html>
    <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>
    </title>
    <style type="text/css">
        #outlook a {
        padding: 0;
        }
        body {
        margin: 0;
        padding: 0;
        -webkit-text-size-adjust: 100%;
        -ms-text-size-adjust: 100%;
        }
        table,
        td {
        border-collapse: collapse;
        mso-table-lspace: 0pt;
        mso-table-rspace: 0pt;
        }
        img {
        border: 0;
        height: auto;
        line-height: 100%;
        outline: none;
        text-decoration: none;
        -ms-interpolation-mode: bicubic;
        }
        p {
        display: block;
        margin: 13px 0;
        }
    </style>
    <style type="text/css">
        @media only screen and (min-width:480px) {
        .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
        }
        }
    </style>
    <style type="text/css">
        @media only screen and (max-width:480px) {
        table.full-width-mobile {
            width: 100% !important;
        }
        td.full-width-mobile {
            width: auto !important;
        }
        }
    </style>
    </head>
    <body style="background-color:#f5f5f5">
    <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
        <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
            <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                <div
                    style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-header">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td
                                    style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                            <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                <tr>
                                                    <td style="width:140px">
                                                    <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                        href="https://dti.group/">
                                                        <img width="140"
                                                        style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                        src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                        height="auto">
                                                    </a>
                                                    </td>
                                                </tr>
                                                </tbody>
                                            </table>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                <strong>Platform Lizenz Warnung von DTI Cognaio license services $baseWebAppLink</strong><strong>
                                                </strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Hallo,</strong><strong>
                                                </strong><br><br><strong>Ihre Platform Lizenz wird ablaufen am: $expiresat GMT+0000</strong><strong><strong>
                                                </strong><br><br><strong>Bitte erneuern Sie Ihren Lizenz innerhalb der nächsten Tage.</strong><strong>
                                                </strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                            class="c--text-subtext" align="left">
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            </div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                Auf bald,<br><strong>Das Cognaio Team</strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;word-break:break-word">
                                            <div style="height:20px">
                                                &nbsp;
                                            </div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div
                    style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer c--courier-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                            class="c--text-subtext" align="center">
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                </td>
            </tr>
            </tbody>
        </table>
        </div>
    </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('95176adf-ce72-454e-aa01-e5b0119a39ff', 'AppEssentialCloseToExpireNotification', 'en', 'Platform License ''$licenseKey'' will expire soon', '<html>
    <head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <title>
    </title>
    <style type="text/css">
        #outlook a {
        padding: 0;
        }
        body {
        margin: 0;
        padding: 0;
        -webkit-text-size-adjust: 100%;
        -ms-text-size-adjust: 100%;
        }
        table,
        td {
        border-collapse: collapse;
        mso-table-lspace: 0pt;
        mso-table-rspace: 0pt;
        }
        img {
        border: 0;
        height: auto;
        line-height: 100%;
        outline: none;
        text-decoration: none;
        -ms-interpolation-mode: bicubic;
        }
        p {
        display: block;
        margin: 13px 0;
        }
    </style>
    <style type="text/css">
        @media only screen and (min-width:480px) {
        .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
        }
        }
    </style>
    <style type="text/css">
        @media only screen and (max-width:480px) {
        table.full-width-mobile {
            width: 100% !important;
        }
        td.full-width-mobile {
            width: auto !important;
        }
        }
    </style>
    </head>
    <body style="background-color:#f5f5f5">
    <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
        <div style="margin:0px auto;max-width:582px">
        <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
            <tbody>
            <tr>
                <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                <div
                    style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-header">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td
                                    style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                            <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                <tr>
                                                    <td style="width:140px">
                                                    <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                        href="https://dti.group/">
                                                        <img width="140"
                                                        style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                        src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                        height="auto">
                                                    </a>
                                                    </td>
                                                </tr>
                                                </tbody>
                                            </table>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                <strong>Platform License Warning of DTI Cognaio license services $baseWebAppLink</strong><strong>
                                                </strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                <strong>Hello,</strong><strong>
                                                </strong><br><br><strong>Your Platform license will expire at: $expiresat GMT+0000</strong><strong><strong>
                                                </strong><br><br><strong>Please consider to renew the license in time.</strong><strong>
                                                </strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                            class="c--text-subtext" align="left">
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                            </div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--block c--block-text">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                            align="left">
                                            <div
                                                style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                Cheers,<br><strong>The Cognaio Team</strong></div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;word-break:break-word">
                                            <div style="height:20px">
                                                &nbsp;
                                            </div>
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                <div
                    style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                    class="c--email-footer c--courier-footer">
                    <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                    cellspacing="0" cellpadding="0" border="0" align="center">
                    <tbody>
                        <tr>
                        <td
                            style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                            <div
                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                            class="mj-column-per-100 outlook-group-fix">
                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                <tbody>
                                <tr>
                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                    <table width="100%"  role="presentation" cellspacing="0" cellpadding="0"
                                        border="0">
                                        <tbody>
                                        <tr>
                                            <td style="font-size:0px;padding:0px;word-break:break-word"
                                            class="c--text-subtext" align="center">
                                            </td>
                                        </tr>
                                        </tbody>
                                    </table>
                                    </td>
                                </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                        </tr>
                    </tbody>
                    </table>
                </div>
                </td>
            </tr>
            </tbody>
        </table>
        </div>
    </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('2a8e5b83-637f-423c-837b-264070968ba7', 'AppEssentialWarnings', 'de', 'Platform Lizenz Warnung', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
            <div style="margin:0px auto;max-width:582px">
                <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
                <tbody>
                    <tr>
                        <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                            <div
                            style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-header">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td
                                                        style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                    <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                        cellspacing="0" cellpadding="0" border="0">
                                                                        <tbody>
                                                                            <tr>
                                                                            <td style="width:140px">
                                                                                <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                                    href="https://dti.group/">
                                                                                <img width="140"
                                                                                    style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                                    src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                                    height="auto">
                                                                                </a>
                                                                            </td>
                                                                            </tr>
                                                                        </tbody>
                                                                    </table>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                        <strong>Platform Lizenz Warnung von DTI Cognaio License services $baseWebAppLink</strong><strong>
                                                                        </strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        <strong>Hallo,</strong><strong> </strong><br><br><strong>
                                                                        Wir haben das folgende Problem mit Ihrer Lizenz festgestellt. Bitten prüfen sie den Zustand Ihrer Platform Lizenz und beheben Sie folgende Probleme:</strong>
																		<br><br>
																		$arrayWarnings
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Auf bald,<br><strong>Das Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                    </tr>
                </tbody>
                </table>
            </div>
        </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('a6c145c0-1d4e-45be-8592-7e40ced69b56', 'AppEssentialWarnings', 'en', 'Platform License Warning', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
            <div style="margin:0px auto;max-width:582px">
                <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
                <tbody>
                    <tr>
                        <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                            <div
                            style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-header">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td
                                                        style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                    <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                        cellspacing="0" cellpadding="0" border="0">
                                                                        <tbody>
                                                                            <tr>
                                                                            <td style="width:140px">
                                                                                <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                                    href="https://dti.group/">
                                                                                <img width="140"
                                                                                    style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                                    src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                                    height="auto">
                                                                                </a>
                                                                            </td>
                                                                            </tr>
                                                                        </tbody>
                                                                    </table>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                        <strong>Platform License Warning of DTI Cognaio License services $baseWebAppLink</strong><strong>
                                                                        </strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        <strong>Hello,</strong><strong> </strong><br><br><strong>
                                                                        We have identified the following issue with your license. Please check the status of your platform license.</strong>
																		<br><br>
																		$arrayWarnings
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Cheers,<br><strong>The Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                    </tr>
                </tbody>
                </table>
            </div>
        </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('06b8cb54-d79a-4ae0-a6d5-6008ee46d4e4', 'AppEssentialFeatureExceedsLimit', 'en', 'Platform License ''$licenseKey'' - Feature ''$feature'' exceeds limit', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
            <div style="margin:0px auto;max-width:582px">
                <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
                <tbody>
                    <tr>
                        <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                            <div
                            style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-header">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td
                                                        style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                    <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                        cellspacing="0" cellpadding="0" border="0">
                                                                        <tbody>
                                                                            <tr>
                                                                            <td style="width:140px">
                                                                                <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                                    href="https://dti.group/">
                                                                                <img width="140"
                                                                                    style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                                    src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                                    height="auto">
                                                                                </a>
                                                                            </td>
                                                                            </tr>
                                                                        </tbody>
                                                                    </table>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                        <strong>Platform License Warning of DTI Cognaio License services $baseWebAppLink</strong><strong>
                                                                        </strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        <strong>Hello,</strong><strong> </strong><br><br><strong>
                                                                        We have discovered a feature in your platform license that exceeds the agreed volume limit. Please adjust your platform license accordingly.</strong>
                                                                        <br><br><ul><li>Feature-Key: $keyOfFeature</li><li>Name: $feature</li><li>Description: $featureDescription</li><li>Limit: $limit</li><li>Exceeds by: $exceedingValue</li>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Cheers,<br><strong>The Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                    </tr>
                </tbody>
                </table>
            </div>
        </div>
    </body>
    </html>');
INSERT INTO cognaio_design.app_notification_templates VALUES ('ff277cde-0590-4270-8b05-c35e6fa26c74', 'AppEssentialFeatureExceedsLimit', 'de', 'Platform License ''$licenseKey'' - Feature ''$feature'' Limit wurde überschritten', '<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <title>
        </title>
        <style type="text/css">
            #outlook a {
            padding: 0;
            }
            body {
            margin: 0;
            padding: 0;
            -webkit-text-size-adjust: 100%;
            -ms-text-size-adjust: 100%;
            }
            table,
            td {
            border-collapse: collapse;
            mso-table-lspace: 0pt;
            mso-table-rspace: 0pt;
            }
            img {
            border: 0;
            height: auto;
            line-height: 100%;
            outline: none;
            text-decoration: none;
            -ms-interpolation-mode: bicubic;
            }
            p {
            display: block;
            margin: 13px 0;
            }
        </style>
        <style type="text/css">
            @media only screen and (min-width:480px) {
            .mj-column-per-100 {
            width: 100% !important;
            max-width: 100%;
            }
            }
        </style>
        <style type="text/css">
            @media only screen and (max-width:480px) {
            table.full-width-mobile {
            width: 100% !important;
            }
            td.full-width-mobile {
            width: auto !important;
            }
            }
        </style>
    </head>
    <body style="background-color:#f5f5f5">
        <div style="padding-bottom:20px;background-color:#f5f5f5" class="c--email-body">
            <div style="margin:0px auto;max-width:582px">
                <table style="width:100%" role="presentation" cellspacing="0" cellpadding="0" border="0" align="center">
                <tbody>
                    <tr>
                        <td style="direction:ltr;font-size:0px;padding:20px 0 0 0;text-align:center">
                            <div
                            style="border-bottom:1px solid #f5f5f5;border-top:6px solid #585986;border-radius:7px 7px 0 0;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-header">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td
                                                        style="background-color:#ffffff;vertical-align:top;padding:0px;padding-top:20px;padding-bottom:20px;padding-left:20px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" align="left">
                                                                    <table style="border-collapse:collapse;border-spacing:0px" role="presentation"
                                                                        cellspacing="0" cellpadding="0" border="0">
                                                                        <tbody>
                                                                            <tr>
                                                                            <td style="width:140px">
                                                                                <a style="color:#2a9edb;font-weight:500;text-decoration:none"
                                                                                    href="https://dti.group/">
                                                                                <img width="140"
                                                                                    style="border:0;display:block;outline:none;text-decoration:none;height:auto;width:100%;font-size:13px;"
                                                                                    src="https://backend-production-librarybucket-1izigk5lryla9.s3.amazonaws.com/57f31dd4-daeb-4022-8c8f-21c810782806/1680006772285_Logo_FINAL_Positive_powered.png"
                                                                                    height="auto">
                                                                                </a>
                                                                            </td>
                                                                            </tr>
                                                                        </tbody>
                                                                    </table>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-h1"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:24px;font-weight:600;line-height:28px;text-align:left;color:#4c4c4c">
                                                                        <strong>Platform Lizenz Warnung von DTI Cognaio License services $baseWebAppLink</strong><strong>
                                                                        </strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        <strong>Hallo,</strong><strong> </strong><br><br><strong>
                                                                        Wir haben in Ihrer Plattformlizenz ein Feature entdeckt, welches das vereinbarte Volumenlimit überschreitet. Bitten passen Sie Ihre Platform Lizenz entsprechend an.</strong>
                                                                        <br><br><ul><li>Feature-Key: $keyOfFeature</li><li>Name: $feature</li><li>Description: $featureDescription</li><li>Limit: $limit</li><li>Exceeds by: $exceedingValue</li>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--block c--block-text">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:8px 30px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:transparent;vertical-align:top;padding:4px 0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word" class="c--text-text"
                                                                    align="left">
                                                                    <div
                                                                        style="font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:18px;text-align:left;color:#4c4c4c">
                                                                        Auf bald,<br><strong>Das Cognaio Team</strong>
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div style="background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:0px;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;word-break:break-word">
                                                                    <div style="height:20px">
                                                                        &nbsp;
                                                                    </div>
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                            <div
                            style="border-radius:0 0 7px 7px;border-bottom:1px solid #f5f5f5;background:#ffffff;background-color:#ffffff;margin:0px auto;max-width:582px"
                            class="c--email-footer c--courier-footer">
                            <table style="background:#ffffff;background-color:#ffffff;width:100%" role="presentation"
                                cellspacing="0" cellpadding="0" border="0" align="center">
                                <tbody>
                                    <tr>
                                        <td
                                        style="border-left:1px solid #f5f5f5;border-right:1px solid #f5f5f5;direction:ltr;font-size:0px;padding:10px;padding-top:0;text-align:center">
                                        <div
                                            style="font-size:0px;text-align:left;direction:ltr;display:inline-block;vertical-align:top;width:100%"
                                            class="mj-column-per-100 outlook-group-fix">
                                            <table width="100%" role="presentation" cellspacing="0" cellpadding="0" border="0">
                                                <tbody>
                                                    <tr>
                                                    <td style="background-color:#ffffff;vertical-align:top;padding:0px;padding-bottom:10px">
                                                        <table width="100%" style="" role="presentation" cellspacing="0" cellpadding="0"
                                                            border="0">
                                                            <tbody>
                                                                <tr>
                                                                <td style="font-size:0px;padding:0px;word-break:break-word"
                                                                    class="c--text-subtext" align="center">
                                                                </td>
                                                                </tr>
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                    </tr>
                                                </tbody>
                                            </table>
                                        </div>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                            </div>
                        </td>
                    </tr>
                </tbody>
                </table>
            </div>
        </div>
    </body>
    </html>');


--
-- TOC entry 3906 (class 0 OID 27740)
-- Dependencies: 229
-- Data for Name: app_notifications; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.app_notifications VALUES ('bcb574c0-6da8-4d9e-a2ad-b626b622a078', 'SubscribeAppKeyRequestNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('79b6176d-0bba-4606-a3f8-7cce71fdc64d', 'OtpNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('c853247c-f4f5-4d43-a30e-c619d709d19a', 'RegisterRequestNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('e94096a2-bffe-445b-a7e4-982aeb83eb34', 'ResubscribeAppKeyRequestForwardNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('b35ddf74-1c67-4732-b796-2f35c135138a', 'ResubscribeAppKeyRequestNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('7614af11-6f34-40f4-b2f8-c14658ad9064', 'SubscribeAppKeyRequestForwardNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('5262b60c-bef7-46fb-b8fd-a917f0dfa51b', 'UnsubscribeAppKeyRequestForwardNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('a31ca353-9d73-40af-a81a-122ef7aa5ab6', 'UnsubscribeAppKeyRequestNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('c8dbe110-d0da-4f3a-a111-3a9c23730b3a', 'RepositoryUpload', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('70a2b52a-80c3-4e92-a8e5-fe06d54c815a', 'AppKeyCloseToExpireNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('977237fb-b177-41b9-a304-14373217b829', 'RegisterRequestCommitNotification', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('8bc304ab-bc65-46f9-8dfa-eea3f85d5882', 'AppEssentialWarnings', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('fd9d28f2-2eb7-442c-83ed-75a3cc523869', 'AppEssentialFeatureExceedsLimit', '{   "to": [],   "cc": [],   "bcc": [] }');
INSERT INTO cognaio_design.app_notifications VALUES ('4e8200db-ddce-4b4a-be64-a37bf4c6ce60', 'AppEssentialCloseToExpireNotification', '{   "to": [],   "cc": [],   "bcc": [] }');

--
-- TOC entry 3909 (class 0 OID 27760)
-- Dependencies: 232
-- Data for Name: app_organizations; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.app_organizations VALUES ('64269559-46f8-4f1f-86b6-15305c674ec6', NULL, 'Administration Layer', NULL, 'The root of all following', NULL, '2023-03-08 10:38:57.817293', NULL, 'this is just a placeholder for now', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAJEAAACQCAYAAAAIhImGAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAAFiUAABYlAUlSJPAAAB8ASURBVHhe7ZwJkBzXed93557ZEyAAipIlmWIEkzIlhjJDqkw7dhIpkitxpeyywwMC6dgUGJV5wIzIOIpjWbJcoVOSKMmxSyIsqlyOKrpMSjIlRYlTZcniEYAECIC4T+Ja7C52d+7pnj7++f9f7+zODmd3FmyS0AJvUX/MTE/369ff93vf970+pi/s68NKUzORMK9Bvz6n0ezvh9efQC2dxveuvQ7+6bOA30QAF+HUORx63/tRS6UQ9PXD53ohXzvb7FTzuncj8BpAyDbCEE2ngrGrroaXYBvJ7tu0K2C/pvNJ/PCjDyKosy9hEwh8hLt24+jatTyG3n1QX71EDhPZFPCZhwGPfQnAY/Mws3sPxvN5rteyhV6TszaZ/cz3zb4CgkSfsc9ELo+prVuBZhMhrYOmB/+zj6CU5ja0YdiX4XZJeDy+VjvLkYVoEbVDpL8LAxEdmsjPQvSnrz5Enm8gKme4jYXIQmQhOk9ZiCxEseV2g4jLqoTouwaicWNoOS6C6AMdEEXbL6V5iOj8Dog8OqXbNu0K+lKEKBVB1HARBB4hCgjRLhxddyEg6idEBUxtsxAZOcmW4eSsNKHqN9GpkknjyXe2IPIJkUeIpgjRrxCi9CxESW67HIh+jhA58xDVCdHbrpkFtjcAcuJ0PjMLkSN+CFGIcPdOQrTm9YGIr83+vFkm8Cdyg4ToWR4MI6Igoo06IVIbWtdCZCGa/WwhWlQWIgtRbPWE6MzELESqiQjRv7QQWYg61AuioAVRIIim40EERrPwQkGU4P5mTzZ++hWcbOTrkhB50cnGYorbWIgsRBai85SFyEIUWxYiC1FsNXmQDg+8no4gasgA/FxkEfr4O69BOH7WGDukscOpM9j9gffjXK6AGtdvEEBt063ddnnXXgtfng98wAVqZQ/Hr3oXmtl+TBd6Q+gnU9xnGj988B7U63Ranb5z6wh3PodDa1fBS/aAiJBVeZyldALVgdUIH36Ebi+jSqBDP0Bl506MF5K0RWtQ6GLt7LYaXHxfzMpW+r4PVR77ZHoEk89/H65XZ18IY6UJ/5FHUcuO0n4puMY2UXuVTD8HZ1t/ltCKhEjGaiYJhEYQgXDSKQQ0UoUj7fvvugY4Owav7iJwGgTqBPYQoqlsgUaSUaMR263ddrlXvxNupcHgUYcbOnxfw5GrrkaYSRGAVNdt2oXEMKZyQ/jxQ5vRcD00GlS9jHDHDkJ0+Zxzl1LAdRqMKBU6P/zEpzgwyijR9y7Znn5hDybyi0Bktu3DTI4DLRV9N5NL4MzQOky98HeoN8rR2PCK8L/4BVQGhhn1omjegsgh5P4yo9GKhKgVnhWRFFWq6X4TmaaTaWy9Zj3cI3vQbMzAq4wjOL4LL/7r92GskDeRyDURoHckqdz0HoSTE3DKx1BrvARv4ggOv2M9R2gCYIrotk27mn1DODY0iGcf+hCCymn47gTCBiPkP/w9jr7xzWj0gEjH2GQUquVSOJMpAH/0RwirJ9H0KgR6EuUXtmImK4giSLTNAogUjdogmMolcXh4NaZ//DgjEPtRrXKwHYT/8CcxpUhOuygStS4L6VXpv7X9UlqxEBmQzIEmUWGEqakuyuSxc3QEL7z7Zmy78b3YeuM/w47rb8KJ0XVcN21GluqnyFDd226pmluFZ258H7b93HvwzA03YOcNN6NIZ3oZ1gzLSIfoKzAKJLHvrVfg6Wuvw9afvxlP3XgTDq9/FyNLgev07oNPgYPDS2VRfMvb8cw//UU8+/PvxbZ3/wJ2rv/HBmjZoNVWOzR6r9StgabPWs9JFLD9puvx4/f8Ep79J+/HU7/wyxh/23oCz/WpVrqXfVQ7XhIQRaFXozH6LGNOsvYppQdRTwyhmhxGOTXAUZ8xRqynWGekkwRp6Sggqb2zuVE4jDqNRJbtDZpllQwBY5HebZt2aX9KuapF6sksSgRcfasm88uCWMArXTtsQ5/dRIrpq8ABM8j+5AkEUx0d3g5Ru9TXRjLJY27ZJpJSYCnN7fuGcS69lgNiPqoqEsmWim4OU/Zy+imtSIgkzT5aEM0v12wmhSpHaJ3ObmoUz+Z2GVJ5PzJ4b+MoPQoA1RZ6r1Qx79TlGDea5WhbbVM18HGZmR0uZ4QzGjDiNRlBtY0c63J7Fdwe2yznoz61A9KSlkXLWS9y3+qDgHZ4PKUCj4MFt6tj0xX+OfvN20XwOIT2oofIGJYGbk1lpZZBQVja1SoaNWp1S8RyC0bNcvTaalcjX06JCvpeipzf+hzVK5GjVJf17oMGiU5LqB2dxhBAybljMkBxvaUgUn9LBEazWPXFZXQBl4N9URtapmOJjkfttdoUwBnu+xKAyElwpJrCMnKSRpzPV6WfSiqPcjrH0Z9hOpETdD9RNINp1QlLK2scUcqkjWRgtavZkCJU923mJcAb3K/2JSfKodq/2ozqst7RKOA62kb3T5UYXasstCtMxw77oZQ2v17ndvPLFIGi93mmUqZkRSfabYb1nb43kcr0LTrGln0C9r8VmXppxUJk9ZMjC5FVbFmIrGLLQmQVWxYiq9iyEFnFloXIKrYsRFaxZSGyii0LkVVsWYisYstCZBVbFiKr2LIQWcWWhcgqtixEVrFlIbKKLQuRVWxZiKxiy0JkFVsWIqvYshBZxZaFyCq2LERWsWUhsootC5FVbFmIrGLLQmQVWxYiq9iyEFnFloXIKrYsRFaxZSGyii0LkVVsWYisYstCZBVbFiKr2LIQWcWWhcgqtixEVrFlIbKKLQuRVWxZiKxiy0JkFVsWIqvYshBZxZaFyCq2LERWsWUhsootC5FVbFmIrGLLQmQVWxYiq9iyEFnFloXIKrYsRFaxZSGyii0LkVVsWYisYstCZBVbFiKr2LIQWcWWhcgqtixEVrFlIbKKrZUJUX8f/P5+BFTYl6CS5rOWR5+1/Hy1cB9qO2hfltCyPnhcN0ikzbJmorVdP2rJfrhJ9UvrptgXftfSgv201Na2pO0WqNs2neKxal3zPmveq4+m73z12Gc/mYzWU/8prRvws74P+/kdX5vmfQp+Xwouj8l8Z9rUa2+tSIhkDDeVhJdMwevP8KALcNMJfu6jM9M0BJcn+P0SanbIS6XQpMGbfPXSaThUkErDp1H9ZALO7PdhpgBHDmM/6qlEBA2dMp3LoJ7vh5ftQ5mQeVw3kvqV4D46ROi8NjXZ94Xiss5tOuSxHz5t0OD+nMQahNwuTBFmQuTxtZHuQyWTQyM5yPcp1LJJrpdDLTGIOj9XMkM8Vh5HhtslBrjdAEoZtiv42H40SOftvphWJkR0nC/H00k1OTo9SKcn0MgmcHh0GAfXrsbBy0bmdOiyURxa0yZ+7vz+6LrLcPTyy/h+BPtHB/HS0AAmcwOoD4yiTHAqqTyNnAGSeTo4Z+BR9JPBA45oXzCnCPdQAQeG17Fd7SPa3+HZfbbrMHWkQ4dXt4mfD162akkdHX0T112DPeveiL0jV6JGMALBlcpwkBF+Qn5sZDX2rvlp7Fx3Ofa88Q04uOZKfr4K+9e9CVvf8hZMZTnoMoQlPUAo86iko2NyaFsT3bvYv1MrFiIw9AqiYoajkE5ucOSepQHqd94KbHsa2Pn8Qr3w3Lw6v6PC3TsQ7tmJkN8H255B8D++jOCBj+D0L34AB950NU7lLmfkGeCo70dpkMASGPWlSYMrkgUc4R6/K+eHce6e+xFu3wHsoF54ge3vjF7bFO7oohe0/0iQdu5eUuEubvMi+7qPx/TUM5h6+5XsH52fyhH2FEqFPIqf+DjX2YdAfdmxHXhuL4Ln9/Azj3nfdoT/5tcZORl1UlnaNcuUHKUzDRjflAYvt3+nViREXn9iDqJpjaSBITSYw8cI1LHf3YSwXEbYDOYELwR8zEufO9X+PTcJgwqXl4FaETh5AsGWL+Pk9Tfg7EAO1YxSIg3PfQoml+mqRlWZTsbSQ9j+sY8hdFyEbhNoskFPfeCr3s8q9EOK+5lTiKBNoemX+rq4As9h0zOogcd77hROXHM1+8MomWBUZJ34Uj6DI1/671zPhe9zA77C4Qvf+kENQXMawS3/zthO5YEiahRZVfvlTBvd7N+pFQmR6gHVIYKplM4yx7OQZRQ4lxvC7gd+D2GjGnlGNBgiFnhrWWpwy5A2D/lGIDaDEoLiETh/8RmcWftW1hhD8DMDjIKsM2h0h+mjlO/DmdwInvrDP4bv1LihPE2QWq9tCrmPpcV+BwRpKbF/OjweLZq1Ck6sfwcjUZYgMDozEk0WkjjwV58nZK7Y4cBQP7iu1ueyOvsVbLzXRBwNBo8QKRLJrm4/YbyYIdJBCiLB1GCN4mi2xIOfyQ5h1wMPwm9UGFAc2ss10vuFipa3q3OdJoe6jO3SVw1yNd50cY6jF/VpYN9+nLr+ZpTTq1lIZ1HPRsW3R0dMp0bwzB98Ao5TNzAEdNzLAdHyoIdCRgtFjMUVkgyxJkCcRsNAVEmrVmSxzbpoOpfC/r/6c8ISmmPRfj1GuTqPiTjB4cbBxntM7VNn3/1+TgiUDo19NQO9mNMZQ64p/lRc9xU4Rc2wMGQk4GzjxfsfQlBzaDBayRiOit4u+DPLl5DGrnCiPwkOjT5NKN3IY/45wrR/L45cfxOq6QxqjEY+oyHYp3KCEP2XT8AlRBr2ZvTTeecv7XjhX8iOtcsnEObg1N96GSd+5u2YyWn2yuiYzLBoHsTBL33JpC81Z6IP+6SeCSrfbxKiu1ElQHXO0gJNDgw8KqgF0EVeWDusPxqsicI+zioUwhkNirlB7L3vQQR1RgE5cFYBYfAZutulZe3ymGLaJT/KSQ6dVef3rfjUZI5zggZVRfD0D3Bi1RCn1Xn2I4sip/djWULEdOa6yjWR41uv7fLYBzekW2elyLewRxQ9365ZXubEXnA94sC+urUZQnQVzhVoI0YW1UXjAwM48NiWWWIIHZiSmdxYdEXhtcq6aMNvM3rRngYiTg4Iks5/acIgO3ezf6dWLERKaSr8BJNyuZbpnMi+zZuBikKH6hiPzppNIXUXzQZN2JhA7cSzcM+cRvP0aXinqJNn+H4MKJdYW5ThuAQkcDAWsB3a2nHoKo5kltkmDyh9eD7/n/Aw9fAX8dJghlGxH7VcAlN0wt7/tBm1s2cXqC6Nj8+pcvYg3JP7UKxXUDa5hemTkaEuVFmIkStTSpWmp4BjxxCUp1CamEFljH08PYHK5HGUzxZRnRjH2epRptincOht7yBAI0xn0cnEiXwaB//yURbWimqCUDuK3ps/hqjgjo3sexTVdXI1AidlUtwlDVFQrxEcQkRjeRr1Ht81I+9PP/m/8IO3XoGjqwo4PlrAieFZMaIcXzuCg28YwYErr8C+j36Ss7Ij8L06Gspp3Fb1EZszo9pt1nCuzhQ3dgil9dewEE2hyj6Uc1kczP+UiQJL6fTIT+G5y/4RvK9/jxGBxDTqcH2X0YWzOgHqcFn9NP7v/Ruxfd1aHBkdxcnBNTg58AacGliDQ+xvOXUZi+fV5rzSsdEBzhB14pVFdUonEhMWoqXUCyKPszMmMP5jKqPDm0wtKp2bcsz//A7rhrV0OmchzPmapusygC6dNPnqsiit8LtTA2/BP1x7A0o/+jvWE5z/0P6CKKp0lOtcVNh2LZzBmYf/mAX1kCn03UIG6FvN9jXDWVwqXk+uGgW+9VWCWibwAoglv8IP21YkcislPP+hu1AbWAsQDDlZlyYCSv1vZvpQpXyzvA81RsSiThym0qYvFqIl1BMiFpmBnGEiCGsQJ0DZb6AUMqp842uYygya61y6TLLAUATIgJBKok6juvk12Paz16GyZ7uJEJoRiR8VTIHD4p3TnJARpLT7RxjPvQFNOi9kkdpg39r720111k+7Ls+h/v2vMFpWmX3ZX1PssFZStcN9hTMNPH/nv0cxfzkcOrXGumUmS9gZbXTslUSe/SwQ2gG2mebEIolSjpMNDRDOVi1ES6gTIl0/CnS2OJ3FgQcegF8p0k6cWquA5IhWEemy3qiwqKz97VdN+nLpbF2j0iwvuog52y4/G6nQ5LJzmVGMbWaxzmih839Ka5q2q2xuyjl1pswa653V15hCP0j1m+gw184i0r4PMQWFTz5BJhV9DD9su8lsWWe3WezXi9j64d/CWIHQsz9S1RTAUeSpCnadJKQdFEllEw2C1nH0hMjnYNj4QQtRN4hQrTASBaxl6Gydb1E9ROcwfMD79tdwbGgA9WTWnJhzqGZ/fk5Of8EIgkzOTmVxfORt8E8fQ4Nt1lgU6cySiuy6co78wfRZv/lfIVR7mRTb5nb9andxad/7RlYjePJJgqPZIwMD2/JMm5xdCqzyOTy/6bcwnh3iMc+mXG6raXiDxbNvjl0Xo/Xamo5HJ2EFhYVoCfWCKKzV6AxCREf4hCigsRSZzGn/v/kmThVYv3A7jVa11SnjBDqpMphEmeuV0utQevZHTF2aOdH4lNKNGzKlmbPaDUzevYk1lS585k06bI863eSwED84vArhd77F+oeNyKFMvz4hCjg78/k+JERbN91pzoLr0opA0olVc8mH4JjbNxKRwJTeso/a1xloC9ESajl6MYiCSs2MbBXVspsgMmegPQfu49/EiYFh08bLjaTRHjmrxBGvOwV0O8RMchVO/OBxgO0KIrmCZQuLbJbZChxMlWMf+4+oZPN08DCQyM21v6hY0B8ZHEDwt19n2i1x1scZZcCC2kgQ0eWVMrZtugtns6MEI7rtRClTUUepTaDrdpRW/wWOY+CKXi1ES0hONhBpZAoiXfagEcppFtb334+wytkZ044prmmoUCmNn3WR03/8b3ByKM9tWgbrrug7QaTaI4uTjz5qIoaihS4ihKqyFeWU3Fhkn3r4c6yFMuaeHtUr3dpslyYDhwYHCdG3GMp0MkKzSTXJ/qp9DQKm5W1334VpQtTqqwaOtlW06WyzU5OcKR4gRL5OcmkyYNqdPW/G9nXyK7jjzujan4XotYfo+J/9GcsqRgnTrs7lWIhashB1aV+KvpuH6OinP01nWIi6yULUpX0p+m4eoiOf+pSByKazl+uigsicbBREnJ2ppm5BpNsq5HoVmMETj+PkoG7cOk+IGIkCXT4hRN0i0ck//TxqWU6/1W6X9jr1ekDUs7C2EF0YiJTOukUiC9EK0wWB6DOfmYNIk3wL0bwsRF3al6Lv5iE6+tnPIpxNZzYSLdQKhUhOSJvXCKLc7MnGPA48sBmoqbCWqeiQgBDxQ6A0RKOFhOjEUG+IBJDARF8G59JrceQLf8HWymSyyUDENvnJ093N8osDnHjkT+CkkqiyXWR635u8HIh8nWwkRFOZkbli/XwgmspHhbVHiFRMm86GLaD4pwG28YPmYrSF6DWASI6qZvUURD/OZVbj2FceA+ozZqYX6MkNvvo6Y823YTPE6f/2SXMxVE/Cgq/d2myXhegC6/WASM7S0xt+qg8z6WEc/85XgGrJXPaoygX0iYeGWDIXesf/8+9zip8yIOmZr25ttstCdIH1ekCkBxKrOaYmrieIxrf/HwRs11x4lQPoD9VD5ka1oI6p37kLZdYgTko3u/e+wd1CdIHVEyJzslHBIrqnyBTW5wvRQM48RhOyeD9SWAvn1E46QDf0yxf8jz7xA8dA5demUfrVXzPPsesZOKjQ79Jmu15PiPTAwZIQsS0L0WsAkTEsDXkqlcNL7/1V+O4kajS9nvwIvXrkC7ZvbkybHEPxp9ejntP9Pnr8+CcjEp3LpZcF0SV8K0gviDSh9ZjKqFcSiWjEajKPv7/izRj/znfhhObGD1ZBTU7G2L6cIGezyHZ378ZYdtDcihGyLzr90K3NdlmILrB6QRRWKwshohHPF6Jqvh8nV63GS//14wjKk3JrdPuq7klCkXVQFJF0n/Kpr3wVM9mCuRNSpwTCzE9GOrMQLSE9naGnHvTEhCAK9QQsjTCTzWLv792HgJFIsyYmMwSaTjVZ/HqMIG4T9Sf+N54avhLTmbzRDFVKD6CSHeL2QxjLFDA2PIKnr7sRjb9+DO7MKdY+dLJD+wsiOiHkG91xW9FzabWzOPtrt5jbVnVvtXlwsO1GscXk96VxeHCEEH2bztQZcDqafg718KQeC2C3dXPdtk2b2MdV3CZKkYpyerhQxXBnm52ayg7g4JYvmUen9Y+tc18CSshqf4Tojo3sb38EEaExg+tSgEgj0ddobEGkR39phOkcIdp8L3xOxXUzvQzFgEGQAvPjBTW/jtLW57DnwY/j2IMPGh3/yEM48R8ewvHNH8Hpj/4hyp/7PLxvfh3emTOcjenkosPtXDjmVltGC3q6QXmEs+4VUfrBt3B4YJXpS/QLIRrNy6mJEjg0PAT/ycfZQc73AkYInQXnvoIwur3Xr9bx/+7ehOnsqjmnauD4s87u1m67ZjggDm7ZQog0nBSJZIxoEOifUrEg0g9jNWlPtR+BcwlAZH7ZrAtERUK0//57EVaKNFB0pV0jPGDK8eicJiNHszqNsDTNCFKKVC0zpFAlvWcarJfhNlk+OzQ4w4HPbR19ZhKT8TWiHcrTaYSxQzj+S7+M+uCwuR1VRq/TIXJCt363S6nvwEgB3ne/wQChH39gCmNkEESkJ4oSjERb7/6QgUjpK3KyolxvSKViJodDW75oBoJSpE5JKJxGjxrweATRRkKU1C+BtJ8gTXF/FzlEikKqDebSGSHSjxgUmc4O3neviSDRz6gEpqhu0iEeYfBdRZQGakGD32lUzkoOcxllmoo05q4bNF0CqGWEUVWQnns3P/eiTdg0Jk9g7P7NmMgPmVMBeuJCRjc/eHUeEDW/9w06VOU6UyTbD8w91jXuh/si3M9tuoswtF074zFHIL28zU5N5/I4+JdbeHh6AEnP+wse/VP9NR+JgrSevb/EIDLXtYwiiEwOT6XM7yYevv8+FtY1A498rizhqCzSe4fjj86pqnhVoW3WUfERlQuKMh43cClBo8eaVejW9cwaR7BDwWFxNF3C+J/8AU4PrYXDPrgF1hSESM98qV/zPwi6uAT9sRHWRE9+m33QD0UwPrAfpv5iAWZuoKvMYPuHP4Sp1BAjbQRp6/cml3WeiDPGQ1u+bH7NRA8rKB3LHubSjY7dPLzIwpoQubRf9GOj2vYShEhPnuoHOw1E99zDdMXC2lMaUzrSZQlKEUSlB+XJgCRsXjKw4o/giqRn1fQLR3W+MtOwkGZEciaBA7twatN92L92NcFlOmJ/nHwCNaaxRpIwz/ape7/n5SczODTECPPEE2yc+yM0ejjS/GoJI4ZqIqcygafvvgMThEGXXwSOS4BUBOs8Vrd22zVeGMaBRx9jila0jeDhoc1Jz/sHGzegzLZqaUX21raXQE3UDpH5ha+kfhksiepAAcd/917WNxUaic430ijnzEzOYR4yy8yIJDyS6iZ+JnJm5sUPNDgtTOr0EzNN/bhCuQj/yH5Mf+ER7Lr+ekzm1rCAFrhMXZyJNQhQlU5oJqLHsM1jO137Pa9aNo19a1YxEhEi9lH3Knnshxc2mGgqZr/ezFnWRBsxyQJZYLYuTwgkOblbu+06MZjD3se2cBBwJLF91UNK3zr5YQrtMofJhg+ahy3Vf4/QROBcIjWRINJUXz/O5KhOSGdQYiQ4/WFCND6JsFgEijNGQXEaHuWzoA7KM/AFRZGF8UwFAeUX6bRiCc1pbjPDAnt8Chg7A3/nTnjffhxnf/9BPPOz78Dh0dWopFnHpHJwOJ3XFX79WqubTtHB7INSG1+duadRF5ceh1ZN5H/trwk9+znJfU7xdXqcfT+FcIafj7+Ew799J49xEEFO+4gikd+vmqt3XTSRS+DIn39utl22J3vw+ELuL6QNMMGC/jdu48yMUHNA6Pn9FkRKyRc1RJqVmXNFHI1mSq2nQLnMI0h7r7kWB2/5IPbdfgf233YHDty20Xw+8G834MAtG7D3tg3Yc/sG7LvtNuy/9dZIt93K9anbbsHe3/h17PiVD+C7178TP7zizZy+r2FNot99zhOWtIFEv3ld1jkhvg8FUZvB9WMKrqmNFva5U7o0UmT6PfMv/jl2/6b6sRH7bmW/2Ze9t/+m6eOBW27Hnp9Zby6lBDxOpRsdexSFe4Pa5LpH33MzXrxlIw7ffif2ch8v0ia7bt+InRs2YteG34H75isRZAgoj2H+BKyi0kUOUTfpgFuq08n6Gbw4MqOe0iyq19ntVyJBrwJZaVi3jyid6PcWJb2vpllnMVqZmZ/68Ar2r58RdhIZ1moZpiweVyrD9hmxZ9U6r7WcIn0pXZQQRaE+nlQfyHHSfLuvphRJFkonKaOCNnoVwK1+dG6/vP4sPKYoeke3FkutQWIhatNr4+zXXuaaVceypaRjXI7jW+22q/17RdhXI8peVBCtJLWAN3XObDRoj3pLObbX9y212m3Xq9l+SxcpREoPC0P5+atbuytN3Y6rXd22OX+tSIh6jZQo72uG8crVrd2Vp9b5tMXUbZvz14qGaHGQfvIjUSuNdRbNc+mtbXnv411M0XW2xdS+7vm3Pa+LFKKVLYHUCZeOtVXTtC9/tRSnXVtYW8WWhcgqtixEVrFlIbKKLQuRVWxZiKxiy0JkFVsWIquY6sP/B/c1Q1Ys+ukKAAAAAElFTkSuQmCC', NULL, NULL, NULL, NULL, NULL, NULL);

--
-- Create initial app organization user for administration layer
--

DO $$ 
DECLARE
    administration_layer_organization_users text[] := array[{{- range .Values.cognaioservice.env.organization.users }}
        {{.}}{{- end }}
    ];
	administration_layer_organization_user text;
	user_key uuid;
BEGIN 
 FOREACH administration_layer_organization_user IN ARRAY administration_layer_organization_users
  loop
    INSERT INTO cognaio_design.app_users (email) VALUES (administration_layer_organization_user) RETURNING key INTO user_key;
    INSERT INTO cognaio_design.app_registered_users (fk_user_key) VALUES (user_key);
    INSERT INTO cognaio_design.app_organization_users (fk_organization_key, fk_user_key, user_permissions) VALUES ('64269559-46f8-4f1f-86b6-15305c674ec6', user_key, '{
    "plans": {
      "can_edit": true,
      "can_create": true,
      "can_delete": true
    },
    "appkey": {
      "can_create": true,
      "can_notify": false,
      "can_request": true,
      "can_unsubscribe": true,
      "can_create_multiple": true
    },
    "audits": {
      "can_view_reports": true,
      "can_download_artifacts": true
    },
    "scopes": {
      "can_edit": true,
      "can_create": true,
      "can_delete": true
    },
    "designer": {
      "can_open": true
    },
    "teamMembers": {
      "can_delete": true,
      "can_invite": true,
      "can_change_permissions": true
    },
    "organizations": {
      "can_edit": true,
      "can_create": true,
      "can_delete": true
    }
  }');
  end loop;
  
  UPDATE cognaio_design.app_notifications set addresses = json_build_object(
    'to', ARRAY_TO_JSON(administration_layer_organization_users),
	 	'cc', ARRAY_TO_JSON('{}'::text[]),
    'bcc', ARRAY_TO_JSON('{}'::text[])) WHERE name ='RepositoryUpload';

END $$;

--
-- Encrypt app template endpoint
--

DO $$ 
DECLARE
  passphrase_templates text := '{{ .Values.cognaioservice.env.tokens.passPhraseTemplates }}';
	endpoints_template_json jsonb := json_build_object(
		'email', json_build_object(
		  'status', 'http://emailservice.{{ .Values.cognaio.namespace }}/api/email/box/status',
		  'inbound', 'http://emailservice.{{ .Values.cognaio.namespace }}/api/email/box/observe',
		  'mailboxDefinitions', 'http://cognaioservice.{{ .Values.cognaio.namespace }}'
		),
		'cognaio', json_build_object(
		  'service', 'http://cognaioservice.{{ .Values.cognaio.namespace }}'
		),
		'imageProvider', json_build_object(
		  'convertService', 'http://imageprovider.{{ .Values.cognaio.namespace }}'
		),
		'objectsProvider', json_build_object(
		  'detectionService', 'http://objectdetectionprovider.{{ .Values.cognaio.namespace }}'
		),
		'repositories', json_build_object(
		  'endpoint', 'http://cognaioflexsearchservice.{{ .Values.cognaio.namespace }}/api/flexsearch'
		),
		'azureOpenAi', json_build_object(
		  'apiKey', '{{ .Values.cognaioservice.env.ai.apikeyAzureOpenAi }}',
		  'endpoint', '{{ .Values.cognaioservice.env.ai.endpointAzureOpenAi }}'
		),
		'nativeOpenAi', json_build_object(
		  'apiKey', '{{ .Values.cognaioservice.env.ai.apikeyNativeOpenAi }}',
		  'endpoint', '{{ .Values.cognaioservice.env.ai.endpointNativeOpenAi }}'
		),
		'azureAiDocumentIntelligence', json_build_object(
		  'model', 'prebuilt-layout',
		  'apiVersion', '2023-07-31',
		  'apiKey', '{{ .Values.cognaioservice.env.ai.apikeyAzureAiDocumentIntelligence }}',
		  'endpoint', '{{ .Values.cognaioservice.env.ai.endpointAzureAiDocumentIntelligence }}'
		),
		'azureCognitiveServicesComputerVision', json_build_object(
		  'apiKey', '{{ .Values.cognaioservice.env.ai.apikeyAzureCognitiveServicesComputervision }}',
		  'endpoint', '{{ .Values.cognaioservice.env.ai.endpointAzureCognitiveServicesComputerVision }}'
		)
	);
BEGIN			
	-- create endpoints
	INSERT INTO cognaio_design.app_templates_endpoint(template)
		VALUES (encode(cognaio_extensions.pgp_sym_encrypt(endpoints_template_json::text, passphrase_templates, 'compress-algo=1, cipher-algo=aes256'), 'base64'));
END $$;

--
-- TOC entry 3915 (class 0 OID 27809)
-- Dependencies: 238
-- Data for Name: app_templates_outbound; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.app_templates_outbound VALUES ('93afc629-2ad9-4a64-acc1-a8c180eb2e11', '2024-03-12 16:50:23.00944', NULL, '{
        "ai": {
            "general": {
                "maxRetries": 3,
                "maxRetriesWaitTimeoutInSec": 2
            },
            "content": {
                "extraction": {
                    "fields": [{
                            "kind": "chain",
                            "cases": [{
                                    "name": "Classify",
                                    "promptInput": "Unterscheide exakt ob es sich bei dem Dokument um eine Rechnung, ein Lieferschein oder sonstiges Dokument handelt. Schreibe jeweils die ein oder andere Information, also Rechnung, Lieferschein oder Sonstiges in das Feld Dokumententyp. Schreibe keine anderen Werte als Rechnung, Lieferschein oder Sonstiges in das Feld. Auch bei ausländischen Dokumenten übersetze den Dokumententyp in Rechnung oder Lieferschein. Wenn es keins von beiden Dokumentenarten ist, schreibe in der Feld Dokumententyp das Wort Sonstiges",
                                    "promptOutput": "Gebe das Ergebnis ausschliesslich als folgende JSON Struktur aus\n[Json Beispiel]\n",
                                    "promptContext": "[Dokument]\n",
                                    "fields": [{
                                            "name": "Dokumententyp",
                                            "type": "Text"
                                        }
                                    ],
                                    "conditions": [{
                                            "expressions": [{
                                                    "field": "Dokumententyp",
                                                    "exp": "/^Rechnung$/i"
                                                }
                                            ],
                                            "operator": "AND",
                                            "trueCases": ["Case-Rechnung"],
                                            "falseCases": null,
                                            "break": true
                                        }, {
                                            "expressions": [{
                                                    "field": "Dokumententyp",
                                                    "exp": "/^Lieferschein$/i"
                                                }
                                            ],
                                            "operator": "AND",
                                            "trueCases": ["Case-Lieferschein"],
                                            "falseCases": null,
                                            "break": true
                                        }, {
                                            "expressions": [{
                                                    "field": "Dokumententyp",
                                                    "exp": "/^Sonstiges$/i"
                                                }
                                            ],
                                            "operator": "AND",
                                            "trueCases": ["Case-Sonstiges"],
                                            "falseCases": null,
                                            "break": true
                                        }
                                    ]
                                }, {
                                    "name": "Case-Rechnung",
                                    "promptInput": "Für die verabreitung von Rechnungsdaten in einem Buchhalstungssystem benötigen wir von dir korrekt und präzise extrahierte Daten aus einem Rechnungsdokument. Erkenne folgende Felder und befolge genaustens die Anweisungen in den Klammern zu jedem Feld. Rechnungssteller_Name (Name des Rechnungsstellers ohne Adressinformationen), Rechnungssteller_Adresse (Anschrift des Rechnungsstellers), Rechnungsempfänger_Name (Name des Rechnungsempfängers), Rechnungsempfänger _Adresse (Anschrift des Rechnungsempfänger), Rechnungsnummer (Nummer der Rechnungen bzw. des Dokumentes, nicht zu verwechseln mit Kundennummern, Auftragsnummern oder sonstigen werten), Rechnungsdatum (Datum der Rechnung oder des Beleges, nicht zu verwechseln mit Lieferdatum, Zahldatum oder sonstigen anderen Daten im Format dd.mm.yyyy),  Lieferscheinnummer (Lieferscheinnummer), Bestellnummer (Bestellnummer), Netto_Betrag (Rechnungssumme vor Steuern im Format 1234,56 ohne sonstige Zeichen), MwSt_Betrag (Gesamtsumme der Mehrwert- oder Umsatzsteuer aller Steuersätze im Format 1234,56 ohne sonstige Zeichen), Brutto_Betrag (Rechnungssumme nach Steuern im Format 1234,56 ohne sonstige Zeichen), Währung (Währung transformiert in 3 stelliger ISO Norm wie zum Beispiel EUR, CHF, USD), IBAN (IBAN Nummer), Ust ID (Umsatzsteueridentifikationsnummer zum Beispiel CHE-123.456.789 oder DE123456789)",
                                    "promptInputTables": {
                                        "testTable": "Suche ebenso aus den Positionen Spalten Artikelbezeichnung, Menge, Einzelpreis und Gesamtpreis aus.\n"
                                    },
                                    "promptOutput": "Gebe das Ergebnis ausschliesslich als folgende JSON Struktur aus\n",
                                    "promptContext": "[Dokument]\n",
                                    "fields": [{
                                            "name": "Rechnungssteller_Name",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungssteller_Adresse",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungsempfänger_Name",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungsempfänger_Adresse",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungsnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungsdatum",
                                            "type": "Text"
                                        }, {
                                            "name": "Bestellnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "Lieferscheinnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "Netto_Betrag",
                                            "type": "Text"
                                        }, {
                                            "name": "Mwst_Betrag",
                                            "type": "Text"
                                        }, {
                                            "name": "Brutto_Betrag",
                                            "type": "Text"
                                        }, {
                                            "name": "Währung",
                                            "type": "Text"
                                        }, {
                                            "name": "IBAN",
                                            "type": "Text"
                                        }, {
                                            "name": "UST_ID",
                                            "type": "Text"
                                        }, {
                                            "kind": "table",
                                            "name": "testTable",
                                            "priority": 2,
                                            "columns": [{
                                                    "name": "Artikelbezeichnung",
                                                    "type": "Text"
                                                }, {
                                                    "name": "Menge",
                                                    "type": "Text"
                                                }, {
                                                    "name": "Einzelpreis",
                                                    "type": "Text"
                                                }, {
                                                    "name": "Gesamtpreis",
                                                    "type": "Text"
                                                }
                                            ]
                                        }
                                    ]
                                }, {
                                    "name": "Case-Lieferschein",
                                    "promptInput": "Für die Verarbeitung von Lieferscheindaten in einem Buchhaltungssystem benötigen wir von dir korrekt und präzise extrahierte Daten aus einem Lieferscheindokument. Erkenne folgende Felder und befolge die Anweisungen in den Klammern zu jedem Feld. Lieferant_Name (Name des Lieferanten ohne Adressinformationen), Lieferant_Adresse (Anschrift des Lieferanten), Warenempfänger_Name (Name des Warenempfängers), Warenempfänger _Adresse (Anschrift des Warenempfängers), Rechnungsnummer (Nummer einer referenzierten Rechnung, nicht zu verwechseln mit Kundennummern, Auftragsnummern, der Lieferscheinnummer oder sonstigen werten), Dokumentendatum (Datum des Lieferschein bzw. des Dokumentes, nicht zu verwechseln mit Lieferdatum, Zahldatum oder sonstigen anderen Daten, gebe immer im Format dd.mm.yyyy aus), Lieferdatum (Datum der Lieferung wenn angegeben und abweichend zum Dokumentendatum, gebe immer im Format dd.mm.yyyy aus),  Lieferscheinnummer (Lieferscheinnummer), Bestellnummer (Bestellnummer), Ust ID (Umsatzsteueridentifikationsnummer zum Beispiel CHE-123.456.789 oder DE123456789)",
                                    "promptInputTables": {
                                        "testTable": "Suche ebenso aus den Positionen Spalten Artikelbezeichnung und Menge\n"
                                    },
                                    "promptOutput": "[Json Beispiel]\n",
                                    "promptContext": "[Dokument]\n",
                                    "fields": [{
                                            "name": "Lieferant_Name",
                                            "type": "Text"
                                        }, {
                                            "name": "Lieferant_Adresse",
                                            "type": "Text"
                                        }, {
                                            "name": "Warenempfänger_Name",
                                            "type": "Text"
                                        }, {
                                            "name": "Warenempfänger_Adresse",
                                            "type": "Text"
                                        }, {
                                            "name": "Rechnungsnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "Dokumentendatum",
                                            "type": "Text"
                                        }, {
                                            "name": "Lieferdatum",
                                            "type": "Text"
                                        }, {
                                            "name": "Bestellnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "Lieferscheinnummer",
                                            "type": "Text"
                                        }, {
                                            "name": "UST_ID",
                                            "type": "Text"
                                        }, {
                                            "kind": "table",
                                            "name": "testTable",
                                            "priority": 2,
                                            "columns": [{
                                                    "name": "Artikelbezeichnung",
                                                    "type": "Text"
                                                }, {
                                                    "name": "Menge",
                                                    "type": "Text"
                                                }
                                            ]
                                        }
                                    ]
                                }, {
                                    "name": "Case-Sonstiges",
                                    "promptInput": "Du bist ein Extraktionssystem für relevante Daten und Informationen aus verschiedensten Dokumenten. Ermittle für dich selbst, um was für eine Dokumentenart es sich handeln könnte. Ermittle auf Basis der Dokumentenart die für die Dokumentenart genau 5 relevantesten Informationen und Daten. Wenn du keine genaue Dokumentenart findest, extrahiere 5 Daten die aus deiner Sicht auf Basis des Textes interessant sein könnten. Dein Output ist immer ein Json in einem bestimmten Format. Siehe dazu das Json Beispiel weiter unten. Angeführt wird das json von dem Feld Dokumentenart und dann die 5 weiteren und relevanten Felder. In folgendem erhälst du ein Beispiel, wie die JSON Struktur aussehen muss. In dem Beispiel heißt es Feld 1, Feld 2 usw., aber du sollst die Felder so benennen, wie Sie tatsächlich laut der Dokumentenart heißen würden. Das Feld Dokumentenart kannst du auch leer lassen, wenn du nicht weißt worum es gehen würde",
                                    "promptOutput": "[Json Beispiel]\n",
                                    "promptContext": "[Dokument]\n",
                                    "fields": [{
                                            "name": "Dokumentenart",
                                            "type": "Text"
                                        }, {
                                            "name": "Feld 1",
                                            "type": "Text"
                                        }, {
                                            "name": "Feld 2",
                                            "type": "Text"
                                        }, {
                                            "name": "Feld 3",
                                            "type": "Text"
                                        }, {
                                            "name": "Feld 4",
                                            "type": "Text"
                                        }, {
                                            "name": "Feld 5",
                                            "type": "Text"
                                        }
                                    ]
                                }
                            ],
                            "chain": ["Classify"]
                        }
                    ],
                    "options": {
                        "enabled": true,
                        "forceUseOfOpenAiAzureClient": true,
                        "cognitiveServicesAiFormRecognizer": {
                            "model": "prebuilt-layout"
                        },
                        "pages": "",
                        "model": "gpt-35-turbo",
                        "requestTimeoutInSec": 60,
                        "temperature": 0.1,
                        "maxTokens": 7000,
                        "fitContentOnTokenOverFlow": true,
                        "charactersPerTokenFactor": 1.8,
                        "promptOcrLineSeparator": "\n"
                    }
                },
                "response": {
                    "options": {
                        "enabled": true,
                        "pages": "",
                        "forceUseOfOpenAiAzureClient": true,
                        "model": "gpt-4",
                        "temperature": 0.1,
                        "maxTokens": 7000,
                        "fitContentOnTokenOverFlow": true,
                        "charactersPerTokenFactor": 1.8,
                        "promptInput": "Beantworte die Frage bzw. erfülle die formulierte Anforderung zum nachfolgendem Dokument und halte dich dabei sehr kurz und prägnant:\n",
                        "promptOutput": "[Stichpunkte]",
                        "promptContext": "[Dokument]\n",
                        "promptOcrLineSeparator": "\n"
                    },
                    "imageOptions": {
                      "enabled": true,
                      "pages": "",
                      "model": "gpt-4-vision-preview",
                      "temperature": 0.1,
                      "maxTokens": 4096,
                      "promptInput": "Beantworte die gestellten Fragen gewissenhaft und ausführlich. Sei nett und vermittle Kompetenz.\n",
                      "promptOutput": "",
                      "promptContext": ""
                    }
                }
            }
        },
        "tegra": {
            "general": {
                "enabled": false,
                "pages": ""
            },
            "options": {
                "projectName": "",
                "documentDefinition": "Invoice",
                "initialProcessState": 0
            },
            "content": {
                "fields": []
            }
        },
        "ocrPages": {
            "general": {
                "enabled": false,
                "pages": "",
                "locationUnitIsPixel": true
            },
            "options": null
        },
        "imagePages": {
            "general": {
                "enabled": false,
                "pages": ""
            },
            "options": null
        },
        "auditArtifacts": {
            "imageEnabled": true,
            "tegraEnabled": false,
            "aiEnabled": true,
            "ocrEnabled": true,
            "feedbackEnabled": true
        }
    }');


--
-- TOC entry 3924 (class 0 OID 27871)
-- Dependencies: 247
-- Data for Name: loc_languages; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

INSERT INTO cognaio_design.loc_languages VALUES ('de', NULL);
INSERT INTO cognaio_design.loc_languages VALUES ('en', NULL);


--
-- TOC entry 3925 (class 0 OID 27874)
-- Dependencies: 248
-- Data for Name: loc_translations; Type: TABLE DATA; Schema: cognaio_design; Owner: postgres
--

--
-- TOC entry 3675 (class 2606 OID 27971)
-- Name: app_content_filter_triggers app_content_filter_triggers_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_content_filter_triggers
    ADD CONSTRAINT app_content_filter_triggers_pkey PRIMARY KEY (filter_trigger_expression);


--
-- TOC entry 3732 (class 2606 OID 64096)
-- Name: app_essentials app_essentials_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_essentials
    ADD CONSTRAINT app_essentials_pkey PRIMARY KEY (key);


--
-- TOC entry 3677 (class 2606 OID 27973)
-- Name: app_keys app_keys_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_keys
    ADD CONSTRAINT app_keys_pkey PRIMARY KEY (key);


--
-- TOC entry 3679 (class 2606 OID 27975)
-- Name: app_notification_templates app_notification_templates_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_notification_templates
    ADD CONSTRAINT app_notification_templates_pkey PRIMARY KEY (key);


--
-- TOC entry 3683 (class 2606 OID 27977)
-- Name: app_notifications app_notifications_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_notifications
    ADD CONSTRAINT app_notifications_pkey PRIMARY KEY (key);


--
-- TOC entry 3687 (class 2606 OID 27979)
-- Name: app_organization_scopes app_organization_scopes_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_scopes
    ADD CONSTRAINT app_organization_scopes_pkey PRIMARY KEY (key);


--
-- TOC entry 3715 (class 2606 OID 27981)
-- Name: def_process_mappings app_outbound_mappings_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT app_outbound_mappings_pkey PRIMARY KEY (key);


--
-- TOC entry 3717 (class 2606 OID 27983)
-- Name: def_process_outbounds app_outbound_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_outbounds
    ADD CONSTRAINT app_outbound_pkey PRIMARY KEY (key);


--
-- TOC entry 3694 (class 2606 OID 27985)
-- Name: app_plans app_plans_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_plans
    ADD CONSTRAINT app_plans_pkey PRIMARY KEY (key);


--
-- TOC entry 3709 (class 2606 OID 27987)
-- Name: def_process_endpoints app_scope_endpoints_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_endpoints
    ADD CONSTRAINT app_scope_endpoints_pkey PRIMARY KEY (key);


--
-- TOC entry 3711 (class 2606 OID 27989)
-- Name: def_process_mailbox_mappings def_process_mailbox_mappings_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailbox_mappings
    ADD CONSTRAINT def_process_mailbox_mappings_pkey PRIMARY KEY (key);


--
-- TOC entry 3713 (class 2606 OID 27991)
-- Name: def_process_mailboxes def_process_mailboxes_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailboxes
    ADD CONSTRAINT def_process_mailboxes_pkey PRIMARY KEY (key);


--
-- TOC entry 3719 (class 2606 OID 61178)
-- Name: def_process_projects def_process_projects_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_projects
    ADD CONSTRAINT def_process_projects_pkey PRIMARY KEY (key, fk_plan);


--
-- TOC entry 3721 (class 2606 OID 27993)
-- Name: def_process_response_transformations def_process_response_transformations_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_response_transformations
    ADD CONSTRAINT def_process_response_transformations_pkey PRIMARY KEY (key);


--
-- TOC entry 3700 (class 2606 OID 27997)
-- Name: app_scopes extraction_scopes_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_scopes
    ADD CONSTRAINT extraction_scopes_pkey PRIMARY KEY (key);


--
-- TOC entry 3724 (class 2606 OID 27999)
-- Name: loc_languages localization_languages_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.loc_languages
    ADD CONSTRAINT localization_languages_pkey PRIMARY KEY (language);


--
-- TOC entry 3727 (class 2606 OID 28001)
-- Name: loc_translations localization_translations_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.loc_translations
    ADD CONSTRAINT localization_translations_pkey PRIMARY KEY (descriptor, fk_language);


--
-- TOC entry 3685 (class 2606 OID 28003)
-- Name: app_notifications name; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_notifications
    ADD CONSTRAINT name UNIQUE (name);


--
-- TOC entry 3681 (class 2606 OID 28005)
-- Name: app_notification_templates name_language; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_notification_templates
    ADD CONSTRAINT name_language UNIQUE (name, language);


--
-- TOC entry 3689 (class 2606 OID 28007)
-- Name: app_organization_users organization_user_key; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT organization_user_key PRIMARY KEY (key);


--
-- TOC entry 3692 (class 2606 OID 28009)
-- Name: app_organizations organizations_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (key);


--
-- TOC entry 3698 (class 2606 OID 28011)
-- Name: app_registration_requests registration_tokens_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registration_requests
    ADD CONSTRAINT registration_tokens_pkey PRIMARY KEY (key);


--
-- TOC entry 3730 (class 2606 OID 28013)
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (key);


--
-- TOC entry 3702 (class 2606 OID 28015)
-- Name: app_templates_endpoint templates_endpoint_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_templates_endpoint
    ADD CONSTRAINT templates_endpoint_pkey PRIMARY KEY (key);


--
-- TOC entry 3704 (class 2606 OID 28017)
-- Name: app_templates_outbound templates_outbound_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_templates_outbound
    ADD CONSTRAINT templates_outbound_pkey PRIMARY KEY (key);


--
-- TOC entry 3696 (class 2606 OID 28019)
-- Name: app_registered_users user_key; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registered_users
    ADD CONSTRAINT user_key PRIMARY KEY (fk_user_key);


--
-- TOC entry 3707 (class 2606 OID 28021)
-- Name: app_users users_pkey; Type: CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_users
    ADD CONSTRAINT users_pkey PRIMARY KEY (key);


--
-- TOC entry 3705 (class 1259 OID 28022)
-- Name: email; Type: INDEX; Schema: cognaio_design; Owner: postgres
--

CREATE UNIQUE INDEX email ON cognaio_design.app_users USING btree (lower(email));


--
-- TOC entry 3690 (class 1259 OID 28023)
-- Name: email_organization; Type: INDEX; Schema: cognaio_design; Owner: postgres
--

CREATE UNIQUE INDEX email_organization ON cognaio_design.app_organizations USING btree (lower(email));


--
-- TOC entry 3725 (class 1259 OID 28024)
-- Name: in_descriptor_cs; Type: INDEX; Schema: cognaio_design; Owner: postgres
--

CREATE UNIQUE INDEX in_descriptor_cs ON cognaio_design.loc_translations USING btree (lower((descriptor)::text), fk_language);


--
-- TOC entry 3722 (class 1259 OID 28025)
-- Name: in_language_cs; Type: INDEX; Schema: cognaio_design; Owner: postgres
--

CREATE UNIQUE INDEX in_language_cs ON cognaio_design.loc_languages USING btree (lower((language)::text));


--
-- TOC entry 3728 (class 1259 OID 28026)
-- Name: schema_version_number; Type: INDEX; Schema: cognaio_design; Owner: postgres
--

CREATE UNIQUE INDEX schema_version_number ON cognaio_design.schema_versions USING btree (lower(version));


--
-- TOC entry 3733 (class 2606 OID 28027)
-- Name: app_keys app_plan; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_keys
    ADD CONSTRAINT app_plan FOREIGN KEY (fk_plan) REFERENCES cognaio_design.app_plans(key);


--
-- TOC entry 3745 (class 2606 OID 28032)
-- Name: app_plans app_scope; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_plans
    ADD CONSTRAINT app_scope FOREIGN KEY (fk_scope) REFERENCES cognaio_design.app_scopes(key);


--
-- TOC entry 3746 (class 2606 OID 28037)
-- Name: app_registered_users createdby; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registered_users
    ADD CONSTRAINT createdby FOREIGN KEY (createdby) REFERENCES cognaio_design.app_registered_users(fk_user_key) NOT VALID;


--
-- TOC entry 3739 (class 2606 OID 28042)
-- Name: app_organization_users createdby; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT createdby FOREIGN KEY (createdby) REFERENCES cognaio_design.app_registered_users(fk_user_key) NOT VALID;


--
-- TOC entry 3740 (class 2606 OID 28047)
-- Name: app_organization_users disabledby; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT disabledby FOREIGN KEY (disabledby) REFERENCES cognaio_design.app_registered_users(fk_user_key) NOT VALID;


--
-- TOC entry 3754 (class 2606 OID 28052)
-- Name: def_process_mappings endpoints_def_key; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT endpoints_def_key FOREIGN KEY (fk_endpoints_def) REFERENCES cognaio_design.def_process_endpoints(key);


--
-- TOC entry 3750 (class 2606 OID 28057)
-- Name: def_process_mailbox_mappings fk_mailbox; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailbox_mappings
    ADD CONSTRAINT fk_mailbox FOREIGN KEY (fk_mailbox) REFERENCES cognaio_design.def_process_mailboxes(key) NOT VALID;


--
-- TOC entry 3736 (class 2606 OID 28062)
-- Name: app_notification_templates fk_notification; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_notification_templates
    ADD CONSTRAINT fk_notification FOREIGN KEY (name) REFERENCES cognaio_design.app_notifications(name) NOT VALID;


--
-- TOC entry 3751 (class 2606 OID 28067)
-- Name: def_process_mailbox_mappings fk_plan; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailbox_mappings
    ADD CONSTRAINT fk_plan FOREIGN KEY (fk_plan) REFERENCES cognaio_design.app_plans(key) NOT VALID;


--
-- TOC entry 3759 (class 2606 OID 28072)
-- Name: def_process_projects fk_plan; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_projects
    ADD CONSTRAINT fk_plan FOREIGN KEY (fk_plan) REFERENCES cognaio_design.app_plans(key) NOT VALID;


--
-- TOC entry 3734 (class 2606 OID 28077)
-- Name: app_keys fkorga; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_keys
    ADD CONSTRAINT fkorga FOREIGN KEY (fk_organization) REFERENCES cognaio_design.app_organizations(key) NOT VALID;


--
-- TOC entry 3735 (class 2606 OID 28082)
-- Name: app_keys fkuser; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_keys
    ADD CONSTRAINT fkuser FOREIGN KEY (fk_user) REFERENCES cognaio_design.app_users(key);


--
-- TOC entry 3760 (class 2606 OID 28087)
-- Name: loc_translations language; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.loc_translations
    ADD CONSTRAINT language FOREIGN KEY (fk_language) REFERENCES cognaio_design.loc_languages(language);


--
-- TOC entry 3752 (class 2606 OID 28092)
-- Name: def_process_mailboxes lockedby_boxmapping; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailboxes
    ADD CONSTRAINT lockedby_boxmapping FOREIGN KEY (lockedby_boxmapping) REFERENCES cognaio_design.def_process_mailbox_mappings(key) NOT VALID;


--
-- TOC entry 3753 (class 2606 OID 28097)
-- Name: def_process_mailboxes lockedby_user; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mailboxes
    ADD CONSTRAINT lockedby_user FOREIGN KEY (lockedby_user) REFERENCES cognaio_design.app_users(key) NOT VALID;


--
-- TOC entry 3747 (class 2606 OID 28102)
-- Name: app_registered_users modifiedby; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registered_users
    ADD CONSTRAINT modifiedby FOREIGN KEY (modifiedby) REFERENCES cognaio_design.app_users(key) NOT VALID;


--
-- TOC entry 3741 (class 2606 OID 28107)
-- Name: app_organization_users modifiedby; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT modifiedby FOREIGN KEY (modifiedby) REFERENCES cognaio_design.app_registered_users(fk_user_key) NOT VALID;


--
-- TOC entry 3737 (class 2606 OID 28112)
-- Name: app_organization_scopes orga_fk; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_scopes
    ADD CONSTRAINT orga_fk FOREIGN KEY (fk_organization_key) REFERENCES cognaio_design.app_organizations(key) NOT VALID;


--
-- TOC entry 3742 (class 2606 OID 28117)
-- Name: app_organization_users organization_fkey; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT organization_fkey FOREIGN KEY (fk_organization_key) REFERENCES cognaio_design.app_organizations(key);


--
-- TOC entry 3749 (class 2606 OID 28122)
-- Name: app_registration_requests organizationkey; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registration_requests
    ADD CONSTRAINT organizationkey FOREIGN KEY (fk_organization) REFERENCES cognaio_design.app_organizations(key);


--
-- TOC entry 3744 (class 2606 OID 28127)
-- Name: app_organizations organizations_fkey; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organizations
    ADD CONSTRAINT organizations_fkey FOREIGN KEY (fk_parent_organization) REFERENCES cognaio_design.app_organizations(key);


--
-- TOC entry 3755 (class 2606 OID 28132)
-- Name: def_process_mappings outbound_def_key; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT outbound_def_key FOREIGN KEY (fk_outbound_def) REFERENCES cognaio_design.def_process_outbounds(key);


--
-- TOC entry 3756 (class 2606 OID 28137)
-- Name: def_process_mappings plan_key; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT plan_key FOREIGN KEY (fk_plan) REFERENCES cognaio_design.app_plans(key);


--
-- TOC entry 3757 (class 2606 OID 28142)
-- Name: def_process_mappings response_transformation_key; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT response_transformation_key FOREIGN KEY (fk_response_transformation) REFERENCES cognaio_design.def_process_response_transformations(key) NOT VALID;


--
-- TOC entry 3738 (class 2606 OID 28147)
-- Name: app_organization_scopes scope_fk; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_scopes
    ADD CONSTRAINT scope_fk FOREIGN KEY (fk_scope_key) REFERENCES cognaio_design.app_scopes(key) NOT VALID;


--
-- TOC entry 3758 (class 2606 OID 28152)
-- Name: def_process_mappings scope_key; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.def_process_mappings
    ADD CONSTRAINT scope_key FOREIGN KEY (fk_scope) REFERENCES cognaio_design.app_scopes(key);


--
-- TOC entry 3748 (class 2606 OID 28157)
-- Name: app_registered_users user_fkey; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_registered_users
    ADD CONSTRAINT user_fkey FOREIGN KEY (fk_user_key) REFERENCES cognaio_design.app_users(key);


--
-- TOC entry 3743 (class 2606 OID 28162)
-- Name: app_organization_users user_fkey; Type: FK CONSTRAINT; Schema: cognaio_design; Owner: postgres
--

ALTER TABLE ONLY cognaio_design.app_organization_users
    ADD CONSTRAINT user_fkey FOREIGN KEY (fk_user_key) REFERENCES cognaio_design.app_registered_users(fk_user_key);


INSERT INTO cognaio_design.schema_versions (version, description) VALUES ('2.2.0.0', 'cognaio version 2.2');


-- Completed on 2024-04-09 17:28:57

--
-- PostgreSQL database dump complete
--
