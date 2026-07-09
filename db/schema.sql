\restrict dbmate

-- Dumped from database version 16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)

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
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: litellm; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA litellm;


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: JobStatus; Type: TYPE; Schema: litellm; Owner: -
--

CREATE TYPE litellm."JobStatus" AS ENUM (
    'ACTIVE',
    'INACTIVE'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: log; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.log (
    id bigint NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    operation text NOT NULL,
    actor text NOT NULL,
    row_id bigint,
    before_state jsonb,
    after_state jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT log_operation_check CHECK ((operation = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: log_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

CREATE SEQUENCE audit.log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: log_id_seq; Type: SEQUENCE OWNED BY; Schema: audit; Owner: -
--

ALTER SEQUENCE audit.log_id_seq OWNED BY audit.log.id;


--
-- Name: LiteLLM_SpendLogs; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SpendLogs" (
    request_id text NOT NULL,
    call_type text NOT NULL,
    api_key text DEFAULT ''::text NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    total_tokens integer DEFAULT 0 NOT NULL,
    prompt_tokens integer DEFAULT 0 NOT NULL,
    completion_tokens integer DEFAULT 0 NOT NULL,
    "startTime" timestamp(3) without time zone NOT NULL,
    "endTime" timestamp(3) without time zone NOT NULL,
    request_duration_ms integer,
    "completionStartTime" timestamp(3) without time zone,
    model text DEFAULT ''::text NOT NULL,
    model_id text DEFAULT ''::text,
    model_group text DEFAULT ''::text,
    custom_llm_provider text DEFAULT ''::text,
    api_base text DEFAULT ''::text,
    "user" text DEFAULT ''::text,
    metadata jsonb DEFAULT '{}'::jsonb,
    cache_hit text DEFAULT ''::text,
    cache_key text DEFAULT ''::text,
    request_tags jsonb DEFAULT '[]'::jsonb,
    team_id text,
    organization_id text,
    end_user text,
    requester_ip_address text,
    messages jsonb DEFAULT '{}'::jsonb,
    response jsonb DEFAULT '{}'::jsonb,
    session_id text,
    status text,
    mcp_namespaced_tool_name text,
    agent_id text,
    proxy_server_request jsonb DEFAULT '{}'::jsonb
);


--
-- Name: DailyTagSpend; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."DailyTagSpend" AS
 SELECT jsonb_array_elements_text(request_tags) AS individual_request_tag,
    date("startTime") AS spend_date,
    count(*) AS log_count,
    sum(spend) AS total_spend
   FROM litellm."LiteLLM_SpendLogs" s
  GROUP BY (jsonb_array_elements_text(request_tags)), (date("startTime"));


--
-- Name: LiteLLM_VerificationToken; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_VerificationToken" (
    token text NOT NULL,
    key_name text,
    key_alias text,
    soft_budget_cooldown boolean DEFAULT false NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    expires timestamp(3) without time zone,
    models text[],
    aliases jsonb DEFAULT '{}'::jsonb NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    router_settings jsonb DEFAULT '{}'::jsonb,
    user_id text,
    team_id text,
    agent_id text,
    project_id text,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_parallel_requests integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    blocked boolean,
    tpm_limit bigint,
    rpm_limit bigint,
    max_budget double precision,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    allowed_cache_controls text[] DEFAULT ARRAY[]::text[],
    allowed_routes text[] DEFAULT ARRAY[]::text[],
    policies text[] DEFAULT ARRAY[]::text[],
    access_group_ids text[] DEFAULT ARRAY[]::text[],
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_max_budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    budget_id text,
    organization_id text,
    object_permission_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_by text,
    last_active timestamp(3) without time zone,
    rotation_count integer DEFAULT 0,
    auto_rotate boolean DEFAULT false,
    rotation_interval text,
    last_rotation_at timestamp(3) without time zone,
    key_rotation_at timestamp(3) without time zone,
    budget_limits jsonb
);


--
-- Name: Last30dKeysBySpend; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."Last30dKeysBySpend" AS
 SELECT l.api_key,
    v.key_alias,
    v.key_name,
    sum(l.spend) AS total_spend
   FROM (litellm."LiteLLM_SpendLogs" l
     LEFT JOIN litellm."LiteLLM_VerificationToken" v ON ((l.api_key = v.token)))
  WHERE (l."startTime" >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY l.api_key, v.key_alias, v.key_name
  ORDER BY (sum(l.spend)) DESC;


--
-- Name: Last30dModelsBySpend; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."Last30dModelsBySpend" AS
 SELECT model,
    sum(spend) AS total_spend
   FROM litellm."LiteLLM_SpendLogs"
  WHERE (("startTime" >= (CURRENT_DATE - '30 days'::interval)) AND (model <> ''::text))
  GROUP BY model
  ORDER BY (sum(spend)) DESC;


--
-- Name: Last30dTopEndUsersSpend; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."Last30dTopEndUsersSpend" AS
 SELECT end_user,
    count(*) AS total_events,
    sum(spend) AS total_spend
   FROM litellm."LiteLLM_SpendLogs"
  WHERE ((end_user <> ''::text) AND (end_user <> USER) AND ("startTime" >= (CURRENT_DATE - '30 days'::interval)))
  GROUP BY end_user
  ORDER BY (sum(spend)) DESC
 LIMIT 100;


--
-- Name: LiteLLM_AccessGroupTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_AccessGroupTable" (
    access_group_id text NOT NULL,
    access_group_name text NOT NULL,
    description text,
    access_model_names text[] DEFAULT ARRAY[]::text[],
    access_mcp_server_ids text[] DEFAULT ARRAY[]::text[],
    access_agent_ids text[] DEFAULT ARRAY[]::text[],
    assigned_team_ids text[] DEFAULT ARRAY[]::text[],
    assigned_key_ids text[] DEFAULT ARRAY[]::text[],
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_AdaptiveRouterSession; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_AdaptiveRouterSession" (
    session_id text NOT NULL,
    router_name text NOT NULL,
    model_name text NOT NULL,
    classified_type text NOT NULL,
    misalignment_count integer DEFAULT 0 NOT NULL,
    stagnation_count integer DEFAULT 0 NOT NULL,
    disengagement_count integer DEFAULT 0 NOT NULL,
    satisfaction_count integer DEFAULT 0 NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    loop_count integer DEFAULT 0 NOT NULL,
    exhaustion_count integer DEFAULT 0 NOT NULL,
    last_user_content text,
    last_assistant_content text,
    tool_call_history jsonb DEFAULT '[]'::jsonb NOT NULL,
    pending_tool_calls jsonb DEFAULT '{}'::jsonb NOT NULL,
    turn_count integer DEFAULT 0 NOT NULL,
    last_processed_turn integer DEFAULT '-1'::integer NOT NULL,
    clean_credit_awarded boolean DEFAULT false NOT NULL,
    terminal_status integer,
    last_activity_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_AdaptiveRouterState; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_AdaptiveRouterState" (
    router_name text NOT NULL,
    request_type text NOT NULL,
    model_name text NOT NULL,
    alpha double precision NOT NULL,
    beta double precision NOT NULL,
    total_samples integer DEFAULT 0 NOT NULL,
    last_updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_AgentsTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_AgentsTable" (
    agent_id text NOT NULL,
    agent_name text NOT NULL,
    litellm_params jsonb,
    agent_card_params jsonb NOT NULL,
    static_headers jsonb DEFAULT '{}'::jsonb,
    extra_headers text[] DEFAULT ARRAY[]::text[],
    agent_access_groups text[] DEFAULT ARRAY[]::text[],
    object_permission_id text,
    spend double precision DEFAULT 0.0 NOT NULL,
    tpm_limit integer,
    rpm_limit integer,
    session_tpm_limit integer,
    session_rpm_limit integer,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_AuditLog; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_AuditLog" (
    id text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    changed_by text DEFAULT ''::text NOT NULL,
    changed_by_api_key text DEFAULT ''::text NOT NULL,
    action text NOT NULL,
    table_name text NOT NULL,
    object_id text NOT NULL,
    before_value jsonb,
    updated_values jsonb
);


--
-- Name: LiteLLM_BudgetTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_BudgetTable" (
    budget_id text NOT NULL,
    max_budget double precision,
    soft_budget double precision,
    max_parallel_requests integer,
    tpm_limit bigint,
    rpm_limit bigint,
    model_max_budget jsonb,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    allowed_models text[] DEFAULT ARRAY[]::text[],
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_CacheConfig; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_CacheConfig" (
    id text DEFAULT 'cache_config'::text NOT NULL,
    cache_settings jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_ClaudeCodePluginTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ClaudeCodePluginTable" (
    id text NOT NULL,
    name text NOT NULL,
    version text,
    description text,
    manifest_json text,
    files_json text DEFAULT '{}'::text,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by text
);


--
-- Name: LiteLLM_Config; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_Config" (
    param_name text NOT NULL,
    param_value jsonb
);


--
-- Name: LiteLLM_ConfigOverrides; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ConfigOverrides" (
    config_type text NOT NULL,
    config_value jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_CredentialsTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_CredentialsTable" (
    credential_id text NOT NULL,
    credential_name text NOT NULL,
    credential_values jsonb NOT NULL,
    credential_info jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_CronJob; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_CronJob" (
    cronjob_id text NOT NULL,
    pod_id text NOT NULL,
    status litellm."JobStatus" DEFAULT 'INACTIVE'::litellm."JobStatus" NOT NULL,
    last_updated timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ttl timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyAgentSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyAgentSpend" (
    id text NOT NULL,
    agent_id text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyEndUserSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyEndUserSpend" (
    id text NOT NULL,
    end_user_id text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyGuardrailMetrics; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyGuardrailMetrics" (
    guardrail_id text NOT NULL,
    date text NOT NULL,
    requests_evaluated bigint DEFAULT 0 NOT NULL,
    passed_count bigint DEFAULT 0 NOT NULL,
    blocked_count bigint DEFAULT 0 NOT NULL,
    flagged_count bigint DEFAULT 0 NOT NULL,
    avg_score double precision,
    avg_latency_ms double precision,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyOrganizationSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyOrganizationSpend" (
    id text NOT NULL,
    organization_id text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyPolicyMetrics; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyPolicyMetrics" (
    policy_id text NOT NULL,
    date text NOT NULL,
    requests_evaluated bigint DEFAULT 0 NOT NULL,
    passed_count bigint DEFAULT 0 NOT NULL,
    blocked_count bigint DEFAULT 0 NOT NULL,
    flagged_count bigint DEFAULT 0 NOT NULL,
    avg_score double precision,
    avg_latency_ms double precision,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyTagSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyTagSpend" (
    id text NOT NULL,
    request_id text,
    tag text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyTeamSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyTeamSpend" (
    id text NOT NULL,
    team_id text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DailyUserSpend; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DailyUserSpend" (
    id text NOT NULL,
    user_id text,
    date text NOT NULL,
    api_key text NOT NULL,
    model text,
    model_group text,
    custom_llm_provider text,
    mcp_namespaced_tool_name text,
    endpoint text,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cache_read_input_tokens bigint DEFAULT 0 NOT NULL,
    cache_creation_input_tokens bigint DEFAULT 0 NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    api_requests bigint DEFAULT 0 NOT NULL,
    successful_requests bigint DEFAULT 0 NOT NULL,
    failed_requests bigint DEFAULT 0 NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_DeletedTeamTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DeletedTeamTable" (
    id text NOT NULL,
    team_id text NOT NULL,
    team_alias text,
    organization_id text,
    object_permission_id text,
    admins text[],
    members text[],
    members_with_roles jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_budget double precision,
    soft_budget double precision,
    spend double precision DEFAULT 0.0 NOT NULL,
    models text[],
    max_parallel_requests integer,
    tpm_limit bigint,
    rpm_limit bigint,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    blocked boolean DEFAULT false NOT NULL,
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_max_budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    router_settings jsonb DEFAULT '{}'::jsonb,
    team_member_permissions text[] DEFAULT ARRAY[]::text[],
    access_group_ids text[] DEFAULT ARRAY[]::text[],
    policies text[] DEFAULT ARRAY[]::text[],
    model_id integer,
    allow_team_guardrail_config boolean DEFAULT false NOT NULL,
    created_at timestamp(3) without time zone,
    updated_at timestamp(3) without time zone,
    deleted_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_by text,
    deleted_by_api_key text,
    litellm_changed_by text
);


--
-- Name: LiteLLM_DeletedVerificationToken; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DeletedVerificationToken" (
    id text NOT NULL,
    token text NOT NULL,
    key_name text,
    key_alias text,
    soft_budget_cooldown boolean DEFAULT false NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    expires timestamp(3) without time zone,
    models text[],
    aliases jsonb DEFAULT '{}'::jsonb NOT NULL,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    user_id text,
    team_id text,
    agent_id text,
    project_id text,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_parallel_requests integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    blocked boolean,
    tpm_limit bigint,
    rpm_limit bigint,
    max_budget double precision,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    allowed_cache_controls text[] DEFAULT ARRAY[]::text[],
    allowed_routes text[] DEFAULT ARRAY[]::text[],
    policies text[] DEFAULT ARRAY[]::text[],
    access_group_ids text[] DEFAULT ARRAY[]::text[],
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_max_budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    router_settings jsonb DEFAULT '{}'::jsonb,
    budget_id text,
    organization_id text,
    object_permission_id text,
    created_at timestamp(3) without time zone,
    created_by text,
    updated_at timestamp(3) without time zone,
    updated_by text,
    last_active timestamp(3) without time zone,
    rotation_count integer DEFAULT 0,
    auto_rotate boolean DEFAULT false,
    rotation_interval text,
    last_rotation_at timestamp(3) without time zone,
    key_rotation_at timestamp(3) without time zone,
    deleted_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_by text,
    deleted_by_api_key text,
    litellm_changed_by text
);


--
-- Name: LiteLLM_DeprecatedVerificationToken; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_DeprecatedVerificationToken" (
    id text NOT NULL,
    token text NOT NULL,
    active_token_id text NOT NULL,
    revoke_at timestamp(3) without time zone NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_EndUserTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_EndUserTable" (
    user_id text NOT NULL,
    alias text,
    spend double precision DEFAULT 0.0 NOT NULL,
    allowed_model_region text,
    default_model text,
    budget_id text,
    object_permission_id text,
    blocked boolean DEFAULT false NOT NULL
);


--
-- Name: LiteLLM_ErrorLogs; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ErrorLogs" (
    request_id text NOT NULL,
    "startTime" timestamp(3) without time zone NOT NULL,
    "endTime" timestamp(3) without time zone NOT NULL,
    api_base text DEFAULT ''::text NOT NULL,
    model_group text DEFAULT ''::text NOT NULL,
    litellm_model_name text DEFAULT ''::text NOT NULL,
    model_id text DEFAULT ''::text NOT NULL,
    request_kwargs jsonb DEFAULT '{}'::jsonb NOT NULL,
    exception_type text DEFAULT ''::text NOT NULL,
    exception_string text DEFAULT ''::text NOT NULL,
    status_code text DEFAULT ''::text NOT NULL
);


--
-- Name: LiteLLM_GuardrailsTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_GuardrailsTable" (
    guardrail_id text NOT NULL,
    guardrail_name text NOT NULL,
    litellm_params jsonb NOT NULL,
    guardrail_info jsonb,
    team_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    submitted_at timestamp(3) without time zone,
    reviewed_at timestamp(3) without time zone
);


--
-- Name: LiteLLM_HealthCheckTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_HealthCheckTable" (
    health_check_id text NOT NULL,
    model_name text NOT NULL,
    model_id text,
    status text NOT NULL,
    healthy_count integer DEFAULT 0 NOT NULL,
    unhealthy_count integer DEFAULT 0 NOT NULL,
    error_message text,
    response_time_ms double precision,
    details jsonb,
    checked_by text,
    checked_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_InvitationLink; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_InvitationLink" (
    id text NOT NULL,
    user_id text NOT NULL,
    is_accepted boolean DEFAULT false NOT NULL,
    accepted_at timestamp(3) without time zone,
    expires_at timestamp(3) without time zone NOT NULL,
    created_at timestamp(3) without time zone NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_JWTKeyMapping; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_JWTKeyMapping" (
    id text NOT NULL,
    jwt_claim_name text NOT NULL,
    jwt_claim_value text NOT NULL,
    token text NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_MCPServerTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_MCPServerTable" (
    server_id text NOT NULL,
    server_name text,
    alias text,
    description text,
    instructions text,
    url text,
    spec_path text,
    transport text DEFAULT 'sse'::text NOT NULL,
    auth_type text,
    credentials jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_by text,
    mcp_info jsonb DEFAULT '{}'::jsonb,
    mcp_access_groups text[],
    allowed_tools text[] DEFAULT ARRAY[]::text[],
    tool_name_to_display_name jsonb DEFAULT '{}'::jsonb,
    tool_name_to_description jsonb DEFAULT '{}'::jsonb,
    extra_headers text[] DEFAULT ARRAY[]::text[],
    static_headers jsonb DEFAULT '{}'::jsonb,
    env_vars jsonb DEFAULT '[]'::jsonb,
    status text DEFAULT 'unknown'::text,
    last_health_check timestamp(3) without time zone,
    health_check_error text,
    command text,
    args text[] DEFAULT ARRAY[]::text[],
    env jsonb DEFAULT '{}'::jsonb,
    authorization_url text,
    token_url text,
    registration_url text,
    oauth2_flow text,
    allow_all_keys boolean DEFAULT false NOT NULL,
    available_on_public_internet boolean DEFAULT true NOT NULL,
    delegate_auth_to_upstream boolean DEFAULT false NOT NULL,
    oauth_passthrough boolean DEFAULT false NOT NULL,
    is_byok boolean DEFAULT false NOT NULL,
    byok_description text[] DEFAULT ARRAY[]::text[],
    byok_api_key_help_url text,
    source_url text,
    timeout double precision,
    approval_status text DEFAULT 'active'::text,
    submitted_by text,
    submitted_at timestamp(3) without time zone,
    reviewed_at timestamp(3) without time zone,
    review_notes text
);


--
-- Name: LiteLLM_MCPToolsetTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_MCPToolsetTable" (
    toolset_id text NOT NULL,
    toolset_name text NOT NULL,
    description text,
    tools jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_MCPUserCredentials; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_MCPUserCredentials" (
    id text NOT NULL,
    user_id text NOT NULL,
    server_id text NOT NULL,
    credential_b64 text NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_MCPUserEnvVars; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_MCPUserEnvVars" (
    id text NOT NULL,
    user_id text NOT NULL,
    server_id text NOT NULL,
    values_b64 text NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_ManagedFileTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ManagedFileTable" (
    id text NOT NULL,
    unified_file_id text NOT NULL,
    file_object jsonb,
    model_mappings jsonb NOT NULL,
    flat_model_file_ids text[] DEFAULT ARRAY[]::text[],
    storage_backend text,
    storage_url text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    team_id text,
    updated_at timestamp(3) without time zone NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ManagedObjectTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ManagedObjectTable" (
    id text NOT NULL,
    unified_object_id text NOT NULL,
    model_object_id text NOT NULL,
    file_object jsonb NOT NULL,
    file_purpose text NOT NULL,
    status text,
    batch_processed boolean DEFAULT false NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    team_id text,
    updated_at timestamp(3) without time zone NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ManagedVectorStoreIndexTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ManagedVectorStoreIndexTable" (
    id text NOT NULL,
    index_name text NOT NULL,
    litellm_params jsonb NOT NULL,
    index_info jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ManagedVectorStoreTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ManagedVectorStoreTable" (
    id text NOT NULL,
    unified_resource_id text NOT NULL,
    resource_object jsonb,
    model_mappings jsonb NOT NULL,
    flat_model_resource_ids text[] DEFAULT ARRAY[]::text[],
    storage_backend text,
    storage_url text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    team_id text,
    updated_at timestamp(3) without time zone NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ManagedVectorStoresTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ManagedVectorStoresTable" (
    vector_store_id text NOT NULL,
    custom_llm_provider text NOT NULL,
    vector_store_name text,
    vector_store_description text,
    vector_store_metadata jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL,
    litellm_credential_name text,
    litellm_params jsonb,
    team_id text,
    user_id text
);


--
-- Name: LiteLLM_MemoryTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_MemoryTable" (
    memory_id text NOT NULL,
    key text NOT NULL,
    value text NOT NULL,
    metadata jsonb,
    user_id text,
    team_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ModelTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ModelTable" (
    id integer NOT NULL,
    aliases jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_ModelTable_id_seq; Type: SEQUENCE; Schema: litellm; Owner: -
--

CREATE SEQUENCE litellm."LiteLLM_ModelTable_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: LiteLLM_ModelTable_id_seq; Type: SEQUENCE OWNED BY; Schema: litellm; Owner: -
--

ALTER SEQUENCE litellm."LiteLLM_ModelTable_id_seq" OWNED BY litellm."LiteLLM_ModelTable".id;


--
-- Name: LiteLLM_ObjectPermissionTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ObjectPermissionTable" (
    object_permission_id text NOT NULL,
    mcp_servers text[] DEFAULT ARRAY[]::text[],
    mcp_access_groups text[] DEFAULT ARRAY[]::text[],
    mcp_tool_permissions jsonb,
    vector_stores text[] DEFAULT ARRAY[]::text[],
    agents text[] DEFAULT ARRAY[]::text[],
    agent_access_groups text[] DEFAULT ARRAY[]::text[],
    models text[] DEFAULT ARRAY[]::text[],
    blocked_tools text[] DEFAULT ARRAY[]::text[],
    mcp_toolsets text[] DEFAULT ARRAY[]::text[],
    search_tools text[] DEFAULT ARRAY[]::text[]
);


--
-- Name: LiteLLM_OrganizationMembership; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_OrganizationMembership" (
    user_id text NOT NULL,
    organization_id text NOT NULL,
    user_role text,
    spend double precision DEFAULT 0.0,
    budget_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: LiteLLM_OrganizationTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_OrganizationTable" (
    organization_id text NOT NULL,
    organization_alias text NOT NULL,
    budget_id text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    models text[],
    spend double precision DEFAULT 0.0 NOT NULL,
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    object_permission_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_PolicyAttachmentTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_PolicyAttachmentTable" (
    attachment_id text NOT NULL,
    policy_name text NOT NULL,
    scope text,
    teams text[] DEFAULT ARRAY[]::text[],
    keys text[] DEFAULT ARRAY[]::text[],
    models text[] DEFAULT ARRAY[]::text[],
    tags text[] DEFAULT ARRAY[]::text[],
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_PolicyTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_PolicyTable" (
    policy_id text NOT NULL,
    policy_name text NOT NULL,
    version_number integer DEFAULT 1 NOT NULL,
    version_status text DEFAULT 'production'::text NOT NULL,
    parent_version_id text,
    is_latest boolean DEFAULT true NOT NULL,
    published_at timestamp(3) without time zone,
    production_at timestamp(3) without time zone,
    inherit text,
    description text,
    guardrails_add text[] DEFAULT ARRAY[]::text[],
    guardrails_remove text[] DEFAULT ARRAY[]::text[],
    condition jsonb DEFAULT '{}'::jsonb,
    pipeline jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_ProjectTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ProjectTable" (
    project_id text NOT NULL,
    project_alias text,
    description text,
    team_id text,
    budget_id text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    models text[],
    spend double precision DEFAULT 0.0 NOT NULL,
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_rpm_limit jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_tpm_limit jsonb DEFAULT '{}'::jsonb NOT NULL,
    blocked boolean DEFAULT false NOT NULL,
    object_permission_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_PromptTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_PromptTable" (
    id text NOT NULL,
    prompt_id text NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    environment text DEFAULT 'development'::text NOT NULL,
    created_by text,
    litellm_params jsonb NOT NULL,
    prompt_info jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_ProxyModelTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ProxyModelTable" (
    model_id text NOT NULL,
    model_name text NOT NULL,
    litellm_params jsonb NOT NULL,
    model_info jsonb,
    blocked boolean DEFAULT false NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text NOT NULL
);


--
-- Name: LiteLLM_SSOConfig; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SSOConfig" (
    id text DEFAULT 'sso_config'::text NOT NULL,
    sso_settings jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_SearchToolsTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SearchToolsTable" (
    search_tool_id text NOT NULL,
    search_tool_name text NOT NULL,
    litellm_params jsonb NOT NULL,
    search_tool_info jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_SkillsTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SkillsTable" (
    skill_id text NOT NULL,
    display_title text,
    description text,
    instructions text,
    source text DEFAULT 'custom'::text NOT NULL,
    latest_version text,
    file_content bytea,
    file_name text,
    file_type text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_SpendLogGuardrailIndex; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SpendLogGuardrailIndex" (
    request_id text NOT NULL,
    guardrail_id text NOT NULL,
    policy_id text,
    start_time timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_SpendLogToolIndex; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_SpendLogToolIndex" (
    request_id text NOT NULL,
    tool_name text NOT NULL,
    start_time timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_TagTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_TagTable" (
    tag_name text NOT NULL,
    description text,
    models text[],
    model_info jsonb,
    spend double precision DEFAULT 0.0 NOT NULL,
    budget_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_TeamMembership; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_TeamMembership" (
    user_id text NOT NULL,
    team_id text NOT NULL,
    spend double precision DEFAULT 0.0 NOT NULL,
    total_spend double precision DEFAULT 0.0 NOT NULL,
    budget_id text
);


--
-- Name: LiteLLM_TeamTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_TeamTable" (
    team_id text NOT NULL,
    team_alias text,
    organization_id text,
    object_permission_id text,
    admins text[],
    members text[],
    members_with_roles jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_budget double precision,
    soft_budget double precision,
    spend double precision DEFAULT 0.0 NOT NULL,
    models text[],
    max_parallel_requests integer,
    tpm_limit bigint,
    rpm_limit bigint,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    blocked boolean DEFAULT false NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_max_budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    router_settings jsonb DEFAULT '{}'::jsonb,
    team_member_permissions text[] DEFAULT ARRAY[]::text[],
    access_group_ids text[] DEFAULT ARRAY[]::text[],
    policies text[] DEFAULT ARRAY[]::text[],
    default_team_member_models text[] DEFAULT ARRAY[]::text[],
    budget_limits jsonb,
    model_id integer,
    allow_team_guardrail_config boolean DEFAULT false NOT NULL
);


--
-- Name: LiteLLM_ToolTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_ToolTable" (
    tool_id text NOT NULL,
    tool_name text NOT NULL,
    origin text,
    input_policy text DEFAULT 'untrusted'::text NOT NULL,
    output_policy text DEFAULT 'untrusted'::text NOT NULL,
    call_count integer DEFAULT 0 NOT NULL,
    assignments jsonb DEFAULT '{}'::jsonb,
    key_hash text,
    team_id text,
    key_alias text,
    user_agent text,
    last_used_at timestamp(3) without time zone,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_by text,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_by text
);


--
-- Name: LiteLLM_UISettings; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_UISettings" (
    id text DEFAULT 'ui_settings'::text NOT NULL,
    ui_settings jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL
);


--
-- Name: LiteLLM_UserNotifications; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_UserNotifications" (
    request_id text NOT NULL,
    user_id text NOT NULL,
    models text[],
    justification text NOT NULL,
    status text NOT NULL
);


--
-- Name: LiteLLM_UserTable; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_UserTable" (
    user_id text NOT NULL,
    user_alias text,
    team_id text,
    sso_user_id text,
    organization_id text,
    object_permission_id text,
    password text,
    teams text[] DEFAULT ARRAY[]::text[],
    user_role text,
    max_budget double precision,
    spend double precision DEFAULT 0.0 NOT NULL,
    user_email text,
    models text[],
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    max_parallel_requests integer,
    tpm_limit bigint,
    rpm_limit bigint,
    budget_duration text,
    budget_reset_at timestamp(3) without time zone,
    allowed_cache_controls text[] DEFAULT ARRAY[]::text[],
    policies text[] DEFAULT ARRAY[]::text[],
    model_spend jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_max_budget jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: LiteLLM_VerificationTokenView; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."LiteLLM_VerificationTokenView" AS
 SELECT v.token,
    v.key_name,
    v.key_alias,
    v.soft_budget_cooldown,
    v.spend,
    v.expires,
    v.models,
    v.aliases,
    v.config,
    v.router_settings,
    v.user_id,
    v.team_id,
    v.agent_id,
    v.project_id,
    v.permissions,
    v.max_parallel_requests,
    v.metadata,
    v.blocked,
    v.tpm_limit,
    v.rpm_limit,
    v.max_budget,
    v.budget_duration,
    v.budget_reset_at,
    v.allowed_cache_controls,
    v.allowed_routes,
    v.policies,
    v.access_group_ids,
    v.model_spend,
    v.model_max_budget,
    v.budget_id,
    v.organization_id,
    v.object_permission_id,
    v.created_at,
    v.created_by,
    v.updated_at,
    v.updated_by,
    v.last_active,
    v.rotation_count,
    v.auto_rotate,
    v.rotation_interval,
    v.last_rotation_at,
    v.key_rotation_at,
    v.budget_limits,
    t.spend AS team_spend,
    t.max_budget AS team_max_budget,
    t.tpm_limit AS team_tpm_limit,
    t.rpm_limit AS team_rpm_limit,
    p.project_alias
   FROM ((litellm."LiteLLM_VerificationToken" v
     LEFT JOIN litellm."LiteLLM_TeamTable" t ON ((v.team_id = t.team_id)))
     LEFT JOIN litellm."LiteLLM_ProjectTable" p ON ((v.project_id = p.project_id)));


--
-- Name: LiteLLM_WorkflowEvent; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_WorkflowEvent" (
    event_id text NOT NULL,
    run_id text NOT NULL,
    event_type text NOT NULL,
    step_name text NOT NULL,
    sequence_number integer NOT NULL,
    data jsonb,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_WorkflowMessage; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_WorkflowMessage" (
    message_id text NOT NULL,
    run_id text NOT NULL,
    role text NOT NULL,
    content text NOT NULL,
    sequence_number integer NOT NULL,
    session_id text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: LiteLLM_WorkflowRun; Type: TABLE; Schema: litellm; Owner: -
--

CREATE TABLE litellm."LiteLLM_WorkflowRun" (
    run_id text NOT NULL,
    session_id text NOT NULL,
    workflow_type text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_by text,
    created_at timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(3) without time zone NOT NULL,
    input jsonb,
    output jsonb,
    metadata jsonb
);


--
-- Name: MonthlyGlobalSpend; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."MonthlyGlobalSpend" AS
 SELECT date("startTime") AS date,
    sum(spend) AS spend
   FROM litellm."LiteLLM_SpendLogs"
  WHERE ("startTime" >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY (date("startTime"));


--
-- Name: MonthlyGlobalSpendPerKey; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."MonthlyGlobalSpendPerKey" AS
 SELECT date("startTime") AS date,
    sum(spend) AS spend,
    api_key
   FROM litellm."LiteLLM_SpendLogs"
  WHERE ("startTime" >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY (date("startTime")), api_key;


--
-- Name: MonthlyGlobalSpendPerUserPerKey; Type: VIEW; Schema: litellm; Owner: -
--

CREATE VIEW litellm."MonthlyGlobalSpendPerUserPerKey" AS
 SELECT date("startTime") AS date,
    sum(spend) AS spend,
    api_key,
    "user"
   FROM litellm."LiteLLM_SpendLogs"
  WHERE ("startTime" >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY (date("startTime")), "user", api_key;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: log id; Type: DEFAULT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.log ALTER COLUMN id SET DEFAULT nextval('audit.log_id_seq'::regclass);


--
-- Name: LiteLLM_ModelTable id; Type: DEFAULT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ModelTable" ALTER COLUMN id SET DEFAULT nextval('litellm."LiteLLM_ModelTable_id_seq"'::regclass);


--
-- Name: log log_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.log
    ADD CONSTRAINT log_pkey PRIMARY KEY (id);


--
-- Name: LiteLLM_AccessGroupTable LiteLLM_AccessGroupTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AccessGroupTable"
    ADD CONSTRAINT "LiteLLM_AccessGroupTable_pkey" PRIMARY KEY (access_group_id);


--
-- Name: LiteLLM_AdaptiveRouterSession LiteLLM_AdaptiveRouterSession_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AdaptiveRouterSession"
    ADD CONSTRAINT "LiteLLM_AdaptiveRouterSession_pkey" PRIMARY KEY (session_id, router_name, model_name);


--
-- Name: LiteLLM_AdaptiveRouterState LiteLLM_AdaptiveRouterState_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AdaptiveRouterState"
    ADD CONSTRAINT "LiteLLM_AdaptiveRouterState_pkey" PRIMARY KEY (router_name, request_type, model_name);


--
-- Name: LiteLLM_AgentsTable LiteLLM_AgentsTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AgentsTable"
    ADD CONSTRAINT "LiteLLM_AgentsTable_pkey" PRIMARY KEY (agent_id);


--
-- Name: LiteLLM_AuditLog LiteLLM_AuditLog_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AuditLog"
    ADD CONSTRAINT "LiteLLM_AuditLog_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_BudgetTable LiteLLM_BudgetTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_BudgetTable"
    ADD CONSTRAINT "LiteLLM_BudgetTable_pkey" PRIMARY KEY (budget_id);


--
-- Name: LiteLLM_CacheConfig LiteLLM_CacheConfig_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_CacheConfig"
    ADD CONSTRAINT "LiteLLM_CacheConfig_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ClaudeCodePluginTable LiteLLM_ClaudeCodePluginTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ClaudeCodePluginTable"
    ADD CONSTRAINT "LiteLLM_ClaudeCodePluginTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ConfigOverrides LiteLLM_ConfigOverrides_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ConfigOverrides"
    ADD CONSTRAINT "LiteLLM_ConfigOverrides_pkey" PRIMARY KEY (config_type);


--
-- Name: LiteLLM_Config LiteLLM_Config_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_Config"
    ADD CONSTRAINT "LiteLLM_Config_pkey" PRIMARY KEY (param_name);


--
-- Name: LiteLLM_CredentialsTable LiteLLM_CredentialsTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_CredentialsTable"
    ADD CONSTRAINT "LiteLLM_CredentialsTable_pkey" PRIMARY KEY (credential_id);


--
-- Name: LiteLLM_CronJob LiteLLM_CronJob_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_CronJob"
    ADD CONSTRAINT "LiteLLM_CronJob_pkey" PRIMARY KEY (cronjob_id);


--
-- Name: LiteLLM_DailyAgentSpend LiteLLM_DailyAgentSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyAgentSpend"
    ADD CONSTRAINT "LiteLLM_DailyAgentSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DailyEndUserSpend LiteLLM_DailyEndUserSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyEndUserSpend"
    ADD CONSTRAINT "LiteLLM_DailyEndUserSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DailyGuardrailMetrics LiteLLM_DailyGuardrailMetrics_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyGuardrailMetrics"
    ADD CONSTRAINT "LiteLLM_DailyGuardrailMetrics_pkey" PRIMARY KEY (guardrail_id, date);


--
-- Name: LiteLLM_DailyOrganizationSpend LiteLLM_DailyOrganizationSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyOrganizationSpend"
    ADD CONSTRAINT "LiteLLM_DailyOrganizationSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DailyPolicyMetrics LiteLLM_DailyPolicyMetrics_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyPolicyMetrics"
    ADD CONSTRAINT "LiteLLM_DailyPolicyMetrics_pkey" PRIMARY KEY (policy_id, date);


--
-- Name: LiteLLM_DailyTagSpend LiteLLM_DailyTagSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyTagSpend"
    ADD CONSTRAINT "LiteLLM_DailyTagSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DailyTeamSpend LiteLLM_DailyTeamSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyTeamSpend"
    ADD CONSTRAINT "LiteLLM_DailyTeamSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DailyUserSpend LiteLLM_DailyUserSpend_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DailyUserSpend"
    ADD CONSTRAINT "LiteLLM_DailyUserSpend_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DeletedTeamTable LiteLLM_DeletedTeamTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DeletedTeamTable"
    ADD CONSTRAINT "LiteLLM_DeletedTeamTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DeletedVerificationToken LiteLLM_DeletedVerificationToken_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DeletedVerificationToken"
    ADD CONSTRAINT "LiteLLM_DeletedVerificationToken_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_DeprecatedVerificationToken LiteLLM_DeprecatedVerificationToken_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_DeprecatedVerificationToken"
    ADD CONSTRAINT "LiteLLM_DeprecatedVerificationToken_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_EndUserTable LiteLLM_EndUserTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_EndUserTable"
    ADD CONSTRAINT "LiteLLM_EndUserTable_pkey" PRIMARY KEY (user_id);


--
-- Name: LiteLLM_ErrorLogs LiteLLM_ErrorLogs_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ErrorLogs"
    ADD CONSTRAINT "LiteLLM_ErrorLogs_pkey" PRIMARY KEY (request_id);


--
-- Name: LiteLLM_GuardrailsTable LiteLLM_GuardrailsTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_GuardrailsTable"
    ADD CONSTRAINT "LiteLLM_GuardrailsTable_pkey" PRIMARY KEY (guardrail_id);


--
-- Name: LiteLLM_HealthCheckTable LiteLLM_HealthCheckTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_HealthCheckTable"
    ADD CONSTRAINT "LiteLLM_HealthCheckTable_pkey" PRIMARY KEY (health_check_id);


--
-- Name: LiteLLM_InvitationLink LiteLLM_InvitationLink_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_InvitationLink"
    ADD CONSTRAINT "LiteLLM_InvitationLink_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_JWTKeyMapping LiteLLM_JWTKeyMapping_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_JWTKeyMapping"
    ADD CONSTRAINT "LiteLLM_JWTKeyMapping_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_MCPServerTable LiteLLM_MCPServerTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_MCPServerTable"
    ADD CONSTRAINT "LiteLLM_MCPServerTable_pkey" PRIMARY KEY (server_id);


--
-- Name: LiteLLM_MCPToolsetTable LiteLLM_MCPToolsetTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_MCPToolsetTable"
    ADD CONSTRAINT "LiteLLM_MCPToolsetTable_pkey" PRIMARY KEY (toolset_id);


--
-- Name: LiteLLM_MCPUserCredentials LiteLLM_MCPUserCredentials_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_MCPUserCredentials"
    ADD CONSTRAINT "LiteLLM_MCPUserCredentials_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_MCPUserEnvVars LiteLLM_MCPUserEnvVars_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_MCPUserEnvVars"
    ADD CONSTRAINT "LiteLLM_MCPUserEnvVars_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ManagedFileTable LiteLLM_ManagedFileTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ManagedFileTable"
    ADD CONSTRAINT "LiteLLM_ManagedFileTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ManagedObjectTable LiteLLM_ManagedObjectTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ManagedObjectTable"
    ADD CONSTRAINT "LiteLLM_ManagedObjectTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ManagedVectorStoreIndexTable LiteLLM_ManagedVectorStoreIndexTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ManagedVectorStoreIndexTable"
    ADD CONSTRAINT "LiteLLM_ManagedVectorStoreIndexTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ManagedVectorStoreTable LiteLLM_ManagedVectorStoreTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ManagedVectorStoreTable"
    ADD CONSTRAINT "LiteLLM_ManagedVectorStoreTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ManagedVectorStoresTable LiteLLM_ManagedVectorStoresTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ManagedVectorStoresTable"
    ADD CONSTRAINT "LiteLLM_ManagedVectorStoresTable_pkey" PRIMARY KEY (vector_store_id);


--
-- Name: LiteLLM_MemoryTable LiteLLM_MemoryTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_MemoryTable"
    ADD CONSTRAINT "LiteLLM_MemoryTable_pkey" PRIMARY KEY (memory_id);


--
-- Name: LiteLLM_ModelTable LiteLLM_ModelTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ModelTable"
    ADD CONSTRAINT "LiteLLM_ModelTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ObjectPermissionTable LiteLLM_ObjectPermissionTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ObjectPermissionTable"
    ADD CONSTRAINT "LiteLLM_ObjectPermissionTable_pkey" PRIMARY KEY (object_permission_id);


--
-- Name: LiteLLM_OrganizationMembership LiteLLM_OrganizationMembership_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationMembership"
    ADD CONSTRAINT "LiteLLM_OrganizationMembership_pkey" PRIMARY KEY (user_id, organization_id);


--
-- Name: LiteLLM_OrganizationTable LiteLLM_OrganizationTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationTable"
    ADD CONSTRAINT "LiteLLM_OrganizationTable_pkey" PRIMARY KEY (organization_id);


--
-- Name: LiteLLM_PolicyAttachmentTable LiteLLM_PolicyAttachmentTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_PolicyAttachmentTable"
    ADD CONSTRAINT "LiteLLM_PolicyAttachmentTable_pkey" PRIMARY KEY (attachment_id);


--
-- Name: LiteLLM_PolicyTable LiteLLM_PolicyTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_PolicyTable"
    ADD CONSTRAINT "LiteLLM_PolicyTable_pkey" PRIMARY KEY (policy_id);


--
-- Name: LiteLLM_ProjectTable LiteLLM_ProjectTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ProjectTable"
    ADD CONSTRAINT "LiteLLM_ProjectTable_pkey" PRIMARY KEY (project_id);


--
-- Name: LiteLLM_PromptTable LiteLLM_PromptTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_PromptTable"
    ADD CONSTRAINT "LiteLLM_PromptTable_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_ProxyModelTable LiteLLM_ProxyModelTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ProxyModelTable"
    ADD CONSTRAINT "LiteLLM_ProxyModelTable_pkey" PRIMARY KEY (model_id);


--
-- Name: LiteLLM_SSOConfig LiteLLM_SSOConfig_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SSOConfig"
    ADD CONSTRAINT "LiteLLM_SSOConfig_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_SearchToolsTable LiteLLM_SearchToolsTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SearchToolsTable"
    ADD CONSTRAINT "LiteLLM_SearchToolsTable_pkey" PRIMARY KEY (search_tool_id);


--
-- Name: LiteLLM_SkillsTable LiteLLM_SkillsTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SkillsTable"
    ADD CONSTRAINT "LiteLLM_SkillsTable_pkey" PRIMARY KEY (skill_id);


--
-- Name: LiteLLM_SpendLogGuardrailIndex LiteLLM_SpendLogGuardrailIndex_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SpendLogGuardrailIndex"
    ADD CONSTRAINT "LiteLLM_SpendLogGuardrailIndex_pkey" PRIMARY KEY (request_id, guardrail_id);


--
-- Name: LiteLLM_SpendLogToolIndex LiteLLM_SpendLogToolIndex_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SpendLogToolIndex"
    ADD CONSTRAINT "LiteLLM_SpendLogToolIndex_pkey" PRIMARY KEY (request_id, tool_name);


--
-- Name: LiteLLM_SpendLogs LiteLLM_SpendLogs_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_SpendLogs"
    ADD CONSTRAINT "LiteLLM_SpendLogs_pkey" PRIMARY KEY (request_id);


--
-- Name: LiteLLM_TagTable LiteLLM_TagTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TagTable"
    ADD CONSTRAINT "LiteLLM_TagTable_pkey" PRIMARY KEY (tag_name);


--
-- Name: LiteLLM_TeamMembership LiteLLM_TeamMembership_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamMembership"
    ADD CONSTRAINT "LiteLLM_TeamMembership_pkey" PRIMARY KEY (user_id, team_id);


--
-- Name: LiteLLM_TeamTable LiteLLM_TeamTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamTable"
    ADD CONSTRAINT "LiteLLM_TeamTable_pkey" PRIMARY KEY (team_id);


--
-- Name: LiteLLM_ToolTable LiteLLM_ToolTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ToolTable"
    ADD CONSTRAINT "LiteLLM_ToolTable_pkey" PRIMARY KEY (tool_id);


--
-- Name: LiteLLM_UISettings LiteLLM_UISettings_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_UISettings"
    ADD CONSTRAINT "LiteLLM_UISettings_pkey" PRIMARY KEY (id);


--
-- Name: LiteLLM_UserNotifications LiteLLM_UserNotifications_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_UserNotifications"
    ADD CONSTRAINT "LiteLLM_UserNotifications_pkey" PRIMARY KEY (request_id);


--
-- Name: LiteLLM_UserTable LiteLLM_UserTable_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_UserTable"
    ADD CONSTRAINT "LiteLLM_UserTable_pkey" PRIMARY KEY (user_id);


--
-- Name: LiteLLM_VerificationToken LiteLLM_VerificationToken_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_VerificationToken"
    ADD CONSTRAINT "LiteLLM_VerificationToken_pkey" PRIMARY KEY (token);


--
-- Name: LiteLLM_WorkflowEvent LiteLLM_WorkflowEvent_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_WorkflowEvent"
    ADD CONSTRAINT "LiteLLM_WorkflowEvent_pkey" PRIMARY KEY (event_id);


--
-- Name: LiteLLM_WorkflowMessage LiteLLM_WorkflowMessage_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_WorkflowMessage"
    ADD CONSTRAINT "LiteLLM_WorkflowMessage_pkey" PRIMARY KEY (message_id);


--
-- Name: LiteLLM_WorkflowRun LiteLLM_WorkflowRun_pkey; Type: CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_WorkflowRun"
    ADD CONSTRAINT "LiteLLM_WorkflowRun_pkey" PRIMARY KEY (run_id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: LiteLLM_AccessGroupTable_access_group_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_AccessGroupTable_access_group_name_key" ON litellm."LiteLLM_AccessGroupTable" USING btree (access_group_name);


--
-- Name: LiteLLM_AgentsTable_agent_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_AgentsTable_agent_name_key" ON litellm."LiteLLM_AgentsTable" USING btree (agent_name);


--
-- Name: LiteLLM_ClaudeCodePluginTable_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ClaudeCodePluginTable_name_key" ON litellm."LiteLLM_ClaudeCodePluginTable" USING btree (name);


--
-- Name: LiteLLM_CredentialsTable_credential_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_CredentialsTable_credential_name_key" ON litellm."LiteLLM_CredentialsTable" USING btree (credential_name);


--
-- Name: LiteLLM_DailyAgentSpend_agent_id_date_api_key_model_custom__key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyAgentSpend_agent_id_date_api_key_model_custom__key" ON litellm."LiteLLM_DailyAgentSpend" USING btree (agent_id, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyAgentSpend_agent_id_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_agent_id_date_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (agent_id, date);


--
-- Name: LiteLLM_DailyAgentSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_api_key_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyAgentSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_date_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (date);


--
-- Name: LiteLLM_DailyAgentSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_endpoint_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyAgentSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyAgentSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyAgentSpend_model_idx" ON litellm."LiteLLM_DailyAgentSpend" USING btree (model);


--
-- Name: LiteLLM_DailyEndUserSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_api_key_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyEndUserSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_date_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (date);


--
-- Name: LiteLLM_DailyEndUserSpend_end_user_id_date_api_key_model_cu_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyEndUserSpend_end_user_id_date_api_key_model_cu_key" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (end_user_id, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyEndUserSpend_end_user_id_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_end_user_id_date_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (end_user_id, date);


--
-- Name: LiteLLM_DailyEndUserSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_endpoint_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyEndUserSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyEndUserSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyEndUserSpend_model_idx" ON litellm."LiteLLM_DailyEndUserSpend" USING btree (model);


--
-- Name: LiteLLM_DailyGuardrailMetrics_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyGuardrailMetrics_date_idx" ON litellm."LiteLLM_DailyGuardrailMetrics" USING btree (date);


--
-- Name: LiteLLM_DailyGuardrailMetrics_guardrail_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyGuardrailMetrics_guardrail_id_idx" ON litellm."LiteLLM_DailyGuardrailMetrics" USING btree (guardrail_id);


--
-- Name: LiteLLM_DailyOrganizationSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_api_key_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyOrganizationSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_date_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (date);


--
-- Name: LiteLLM_DailyOrganizationSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_endpoint_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyOrganizationSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyOrganizationSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_model_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (model);


--
-- Name: LiteLLM_DailyOrganizationSpend_organization_id_date_api_key_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyOrganizationSpend_organization_id_date_api_key_key" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (organization_id, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyOrganizationSpend_organization_id_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyOrganizationSpend_organization_id_date_idx" ON litellm."LiteLLM_DailyOrganizationSpend" USING btree (organization_id, date);


--
-- Name: LiteLLM_DailyPolicyMetrics_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyPolicyMetrics_date_idx" ON litellm."LiteLLM_DailyPolicyMetrics" USING btree (date);


--
-- Name: LiteLLM_DailyPolicyMetrics_policy_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyPolicyMetrics_policy_id_idx" ON litellm."LiteLLM_DailyPolicyMetrics" USING btree (policy_id);


--
-- Name: LiteLLM_DailyTagSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_api_key_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyTagSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_date_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (date);


--
-- Name: LiteLLM_DailyTagSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_endpoint_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyTagSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyTagSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_model_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (model);


--
-- Name: LiteLLM_DailyTagSpend_tag_date_api_key_model_custom_llm_pro_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyTagSpend_tag_date_api_key_model_custom_llm_pro_key" ON litellm."LiteLLM_DailyTagSpend" USING btree (tag, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyTagSpend_tag_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTagSpend_tag_date_idx" ON litellm."LiteLLM_DailyTagSpend" USING btree (tag, date);


--
-- Name: LiteLLM_DailyTeamSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_api_key_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyTeamSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_date_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (date);


--
-- Name: LiteLLM_DailyTeamSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_endpoint_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyTeamSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyTeamSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_model_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (model);


--
-- Name: LiteLLM_DailyTeamSpend_team_id_date_api_key_model_custom_ll_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyTeamSpend_team_id_date_api_key_model_custom_ll_key" ON litellm."LiteLLM_DailyTeamSpend" USING btree (team_id, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyTeamSpend_team_id_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyTeamSpend_team_id_date_idx" ON litellm."LiteLLM_DailyTeamSpend" USING btree (team_id, date);


--
-- Name: LiteLLM_DailyUserSpend_api_key_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_api_key_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (api_key);


--
-- Name: LiteLLM_DailyUserSpend_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_date_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (date);


--
-- Name: LiteLLM_DailyUserSpend_endpoint_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_endpoint_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (endpoint);


--
-- Name: LiteLLM_DailyUserSpend_mcp_namespaced_tool_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_mcp_namespaced_tool_name_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (mcp_namespaced_tool_name);


--
-- Name: LiteLLM_DailyUserSpend_model_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_model_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (model);


--
-- Name: LiteLLM_DailyUserSpend_user_id_date_api_key_model_custom_ll_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DailyUserSpend_user_id_date_api_key_model_custom_ll_key" ON litellm."LiteLLM_DailyUserSpend" USING btree (user_id, date, api_key, model, custom_llm_provider, mcp_namespaced_tool_name, endpoint);


--
-- Name: LiteLLM_DailyUserSpend_user_id_date_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DailyUserSpend_user_id_date_idx" ON litellm."LiteLLM_DailyUserSpend" USING btree (user_id, date);


--
-- Name: LiteLLM_DeletedTeamTable_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedTeamTable_created_at_idx" ON litellm."LiteLLM_DeletedTeamTable" USING btree (created_at);


--
-- Name: LiteLLM_DeletedTeamTable_deleted_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedTeamTable_deleted_at_idx" ON litellm."LiteLLM_DeletedTeamTable" USING btree (deleted_at);


--
-- Name: LiteLLM_DeletedTeamTable_organization_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedTeamTable_organization_id_idx" ON litellm."LiteLLM_DeletedTeamTable" USING btree (organization_id);


--
-- Name: LiteLLM_DeletedTeamTable_team_alias_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedTeamTable_team_alias_idx" ON litellm."LiteLLM_DeletedTeamTable" USING btree (team_alias);


--
-- Name: LiteLLM_DeletedTeamTable_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedTeamTable_team_id_idx" ON litellm."LiteLLM_DeletedTeamTable" USING btree (team_id);


--
-- Name: LiteLLM_DeletedVerificationToken_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_created_at_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (created_at);


--
-- Name: LiteLLM_DeletedVerificationToken_deleted_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_deleted_at_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (deleted_at);


--
-- Name: LiteLLM_DeletedVerificationToken_key_alias_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_key_alias_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (key_alias);


--
-- Name: LiteLLM_DeletedVerificationToken_organization_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_organization_id_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (organization_id);


--
-- Name: LiteLLM_DeletedVerificationToken_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_team_id_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (team_id);


--
-- Name: LiteLLM_DeletedVerificationToken_token_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_token_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (token);


--
-- Name: LiteLLM_DeletedVerificationToken_user_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeletedVerificationToken_user_id_idx" ON litellm."LiteLLM_DeletedVerificationToken" USING btree (user_id);


--
-- Name: LiteLLM_DeprecatedVerificationToken_revoke_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeprecatedVerificationToken_revoke_at_idx" ON litellm."LiteLLM_DeprecatedVerificationToken" USING btree (revoke_at);


--
-- Name: LiteLLM_DeprecatedVerificationToken_token_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_DeprecatedVerificationToken_token_key" ON litellm."LiteLLM_DeprecatedVerificationToken" USING btree (token);


--
-- Name: LiteLLM_DeprecatedVerificationToken_token_revoke_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_DeprecatedVerificationToken_token_revoke_at_idx" ON litellm."LiteLLM_DeprecatedVerificationToken" USING btree (token, revoke_at);


--
-- Name: LiteLLM_GuardrailsTable_guardrail_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_GuardrailsTable_guardrail_name_key" ON litellm."LiteLLM_GuardrailsTable" USING btree (guardrail_name);


--
-- Name: LiteLLM_GuardrailsTable_status_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_GuardrailsTable_status_idx" ON litellm."LiteLLM_GuardrailsTable" USING btree (status);


--
-- Name: LiteLLM_HealthCheckTable_checked_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_HealthCheckTable_checked_at_idx" ON litellm."LiteLLM_HealthCheckTable" USING btree (checked_at);


--
-- Name: LiteLLM_HealthCheckTable_model_id_model_name_checked_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_HealthCheckTable_model_id_model_name_checked_at_idx" ON litellm."LiteLLM_HealthCheckTable" USING btree (model_id, model_name, checked_at DESC);


--
-- Name: LiteLLM_HealthCheckTable_model_name_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_HealthCheckTable_model_name_idx" ON litellm."LiteLLM_HealthCheckTable" USING btree (model_name);


--
-- Name: LiteLLM_HealthCheckTable_status_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_HealthCheckTable_status_idx" ON litellm."LiteLLM_HealthCheckTable" USING btree (status);


--
-- Name: LiteLLM_JWTKeyMapping_jwt_claim_name_jwt_claim_value_is_act_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_JWTKeyMapping_jwt_claim_name_jwt_claim_value_is_act_idx" ON litellm."LiteLLM_JWTKeyMapping" USING btree (jwt_claim_name, jwt_claim_value, is_active);


--
-- Name: LiteLLM_JWTKeyMapping_jwt_claim_name_jwt_claim_value_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_JWTKeyMapping_jwt_claim_name_jwt_claim_value_key" ON litellm."LiteLLM_JWTKeyMapping" USING btree (jwt_claim_name, jwt_claim_value);


--
-- Name: LiteLLM_MCPServerTable_approval_status_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_MCPServerTable_approval_status_idx" ON litellm."LiteLLM_MCPServerTable" USING btree (approval_status);


--
-- Name: LiteLLM_MCPToolsetTable_toolset_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_MCPToolsetTable_toolset_name_key" ON litellm."LiteLLM_MCPToolsetTable" USING btree (toolset_name);


--
-- Name: LiteLLM_MCPUserCredentials_user_id_server_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_MCPUserCredentials_user_id_server_id_key" ON litellm."LiteLLM_MCPUserCredentials" USING btree (user_id, server_id);


--
-- Name: LiteLLM_MCPUserEnvVars_server_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_MCPUserEnvVars_server_id_idx" ON litellm."LiteLLM_MCPUserEnvVars" USING btree (server_id);


--
-- Name: LiteLLM_MCPUserEnvVars_user_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_MCPUserEnvVars_user_id_idx" ON litellm."LiteLLM_MCPUserEnvVars" USING btree (user_id);


--
-- Name: LiteLLM_MCPUserEnvVars_user_id_server_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_MCPUserEnvVars_user_id_server_id_key" ON litellm."LiteLLM_MCPUserEnvVars" USING btree (user_id, server_id);


--
-- Name: LiteLLM_ManagedFileTable_team_id_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedFileTable_team_id_created_at_idx" ON litellm."LiteLLM_ManagedFileTable" USING btree (team_id, created_at DESC);


--
-- Name: LiteLLM_ManagedFileTable_unified_file_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedFileTable_unified_file_id_idx" ON litellm."LiteLLM_ManagedFileTable" USING btree (unified_file_id);


--
-- Name: LiteLLM_ManagedFileTable_unified_file_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ManagedFileTable_unified_file_id_key" ON litellm."LiteLLM_ManagedFileTable" USING btree (unified_file_id);


--
-- Name: LiteLLM_ManagedObjectTable_model_object_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedObjectTable_model_object_id_idx" ON litellm."LiteLLM_ManagedObjectTable" USING btree (model_object_id);


--
-- Name: LiteLLM_ManagedObjectTable_model_object_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ManagedObjectTable_model_object_id_key" ON litellm."LiteLLM_ManagedObjectTable" USING btree (model_object_id);


--
-- Name: LiteLLM_ManagedObjectTable_team_id_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedObjectTable_team_id_created_at_idx" ON litellm."LiteLLM_ManagedObjectTable" USING btree (team_id, created_at DESC);


--
-- Name: LiteLLM_ManagedObjectTable_unified_object_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedObjectTable_unified_object_id_idx" ON litellm."LiteLLM_ManagedObjectTable" USING btree (unified_object_id);


--
-- Name: LiteLLM_ManagedObjectTable_unified_object_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ManagedObjectTable_unified_object_id_key" ON litellm."LiteLLM_ManagedObjectTable" USING btree (unified_object_id);


--
-- Name: LiteLLM_ManagedVectorStoreIndexTable_index_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ManagedVectorStoreIndexTable_index_name_key" ON litellm."LiteLLM_ManagedVectorStoreIndexTable" USING btree (index_name);


--
-- Name: LiteLLM_ManagedVectorStoreTable_team_id_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedVectorStoreTable_team_id_created_at_idx" ON litellm."LiteLLM_ManagedVectorStoreTable" USING btree (team_id, created_at DESC);


--
-- Name: LiteLLM_ManagedVectorStoreTable_unified_resource_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedVectorStoreTable_unified_resource_id_idx" ON litellm."LiteLLM_ManagedVectorStoreTable" USING btree (unified_resource_id);


--
-- Name: LiteLLM_ManagedVectorStoreTable_unified_resource_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ManagedVectorStoreTable_unified_resource_id_key" ON litellm."LiteLLM_ManagedVectorStoreTable" USING btree (unified_resource_id);


--
-- Name: LiteLLM_ManagedVectorStoresTable_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedVectorStoresTable_team_id_idx" ON litellm."LiteLLM_ManagedVectorStoresTable" USING btree (team_id);


--
-- Name: LiteLLM_ManagedVectorStoresTable_user_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ManagedVectorStoresTable_user_id_idx" ON litellm."LiteLLM_ManagedVectorStoresTable" USING btree (user_id);


--
-- Name: LiteLLM_MemoryTable_key_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_MemoryTable_key_key" ON litellm."LiteLLM_MemoryTable" USING btree (key);


--
-- Name: LiteLLM_MemoryTable_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_MemoryTable_team_id_idx" ON litellm."LiteLLM_MemoryTable" USING btree (team_id);


--
-- Name: LiteLLM_MemoryTable_user_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_MemoryTable_user_id_idx" ON litellm."LiteLLM_MemoryTable" USING btree (user_id);


--
-- Name: LiteLLM_OrganizationMembership_user_id_organization_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_OrganizationMembership_user_id_organization_id_key" ON litellm."LiteLLM_OrganizationMembership" USING btree (user_id, organization_id);


--
-- Name: LiteLLM_PolicyTable_policy_name_version_number_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_PolicyTable_policy_name_version_number_key" ON litellm."LiteLLM_PolicyTable" USING btree (policy_name, version_number);


--
-- Name: LiteLLM_PolicyTable_policy_name_version_status_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_PolicyTable_policy_name_version_status_idx" ON litellm."LiteLLM_PolicyTable" USING btree (policy_name, version_status);


--
-- Name: LiteLLM_PromptTable_prompt_id_environment_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_PromptTable_prompt_id_environment_idx" ON litellm."LiteLLM_PromptTable" USING btree (prompt_id, environment);


--
-- Name: LiteLLM_PromptTable_prompt_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_PromptTable_prompt_id_idx" ON litellm."LiteLLM_PromptTable" USING btree (prompt_id);


--
-- Name: LiteLLM_PromptTable_prompt_id_version_environment_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_PromptTable_prompt_id_version_environment_key" ON litellm."LiteLLM_PromptTable" USING btree (prompt_id, version, environment);


--
-- Name: LiteLLM_SearchToolsTable_search_tool_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_SearchToolsTable_search_tool_name_key" ON litellm."LiteLLM_SearchToolsTable" USING btree (search_tool_name);


--
-- Name: LiteLLM_SpendLogGuardrailIndex_guardrail_id_start_time_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogGuardrailIndex_guardrail_id_start_time_idx" ON litellm."LiteLLM_SpendLogGuardrailIndex" USING btree (guardrail_id, start_time);


--
-- Name: LiteLLM_SpendLogGuardrailIndex_policy_id_start_time_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogGuardrailIndex_policy_id_start_time_idx" ON litellm."LiteLLM_SpendLogGuardrailIndex" USING btree (policy_id, start_time);


--
-- Name: LiteLLM_SpendLogToolIndex_tool_name_start_time_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogToolIndex_tool_name_start_time_idx" ON litellm."LiteLLM_SpendLogToolIndex" USING btree (tool_name, start_time);


--
-- Name: LiteLLM_SpendLogs_end_user_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogs_end_user_idx" ON litellm."LiteLLM_SpendLogs" USING btree (end_user);


--
-- Name: LiteLLM_SpendLogs_session_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogs_session_id_idx" ON litellm."LiteLLM_SpendLogs" USING btree (session_id);


--
-- Name: LiteLLM_SpendLogs_startTime_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogs_startTime_idx" ON litellm."LiteLLM_SpendLogs" USING btree ("startTime");


--
-- Name: LiteLLM_SpendLogs_startTime_request_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_SpendLogs_startTime_request_id_idx" ON litellm."LiteLLM_SpendLogs" USING btree ("startTime", request_id);


--
-- Name: LiteLLM_TeamTable_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_TeamTable_created_at_idx" ON litellm."LiteLLM_TeamTable" USING btree (created_at);


--
-- Name: LiteLLM_TeamTable_model_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_TeamTable_model_id_key" ON litellm."LiteLLM_TeamTable" USING btree (model_id);


--
-- Name: LiteLLM_TeamTable_organization_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_TeamTable_organization_id_idx" ON litellm."LiteLLM_TeamTable" USING btree (organization_id);


--
-- Name: LiteLLM_TeamTable_team_alias_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_TeamTable_team_alias_idx" ON litellm."LiteLLM_TeamTable" USING btree (team_alias);


--
-- Name: LiteLLM_ToolTable_input_policy_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ToolTable_input_policy_idx" ON litellm."LiteLLM_ToolTable" USING btree (input_policy);


--
-- Name: LiteLLM_ToolTable_output_policy_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ToolTable_output_policy_idx" ON litellm."LiteLLM_ToolTable" USING btree (output_policy);


--
-- Name: LiteLLM_ToolTable_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_ToolTable_team_id_idx" ON litellm."LiteLLM_ToolTable" USING btree (team_id);


--
-- Name: LiteLLM_ToolTable_tool_name_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_ToolTable_tool_name_key" ON litellm."LiteLLM_ToolTable" USING btree (tool_name);


--
-- Name: LiteLLM_UserTable_sso_user_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_UserTable_sso_user_id_key" ON litellm."LiteLLM_UserTable" USING btree (sso_user_id);


--
-- Name: LiteLLM_VerificationToken_budget_reset_at_expires_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_VerificationToken_budget_reset_at_expires_idx" ON litellm."LiteLLM_VerificationToken" USING btree (budget_reset_at, expires);


--
-- Name: LiteLLM_VerificationToken_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_VerificationToken_team_id_idx" ON litellm."LiteLLM_VerificationToken" USING btree (team_id);


--
-- Name: LiteLLM_VerificationToken_user_id_team_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_VerificationToken_user_id_team_id_idx" ON litellm."LiteLLM_VerificationToken" USING btree (user_id, team_id);


--
-- Name: LiteLLM_WorkflowEvent_run_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowEvent_run_id_idx" ON litellm."LiteLLM_WorkflowEvent" USING btree (run_id);


--
-- Name: LiteLLM_WorkflowEvent_run_id_sequence_number_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_WorkflowEvent_run_id_sequence_number_key" ON litellm."LiteLLM_WorkflowEvent" USING btree (run_id, sequence_number);


--
-- Name: LiteLLM_WorkflowMessage_run_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowMessage_run_id_idx" ON litellm."LiteLLM_WorkflowMessage" USING btree (run_id);


--
-- Name: LiteLLM_WorkflowMessage_run_id_sequence_number_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_WorkflowMessage_run_id_sequence_number_key" ON litellm."LiteLLM_WorkflowMessage" USING btree (run_id, sequence_number);


--
-- Name: LiteLLM_WorkflowRun_created_at_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowRun_created_at_idx" ON litellm."LiteLLM_WorkflowRun" USING btree (created_at);


--
-- Name: LiteLLM_WorkflowRun_created_by_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowRun_created_by_idx" ON litellm."LiteLLM_WorkflowRun" USING btree (created_by);


--
-- Name: LiteLLM_WorkflowRun_session_id_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowRun_session_id_idx" ON litellm."LiteLLM_WorkflowRun" USING btree (session_id);


--
-- Name: LiteLLM_WorkflowRun_session_id_key; Type: INDEX; Schema: litellm; Owner: -
--

CREATE UNIQUE INDEX "LiteLLM_WorkflowRun_session_id_key" ON litellm."LiteLLM_WorkflowRun" USING btree (session_id);


--
-- Name: LiteLLM_WorkflowRun_workflow_type_status_idx; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX "LiteLLM_WorkflowRun_workflow_type_status_idx" ON litellm."LiteLLM_WorkflowRun" USING btree (workflow_type, status);


--
-- Name: idx_adaptive_router_session_activity; Type: INDEX; Schema: litellm; Owner: -
--

CREATE INDEX idx_adaptive_router_session_activity ON litellm."LiteLLM_AdaptiveRouterSession" USING btree (last_activity_at);


--
-- Name: LiteLLM_AgentsTable LiteLLM_AgentsTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_AgentsTable"
    ADD CONSTRAINT "LiteLLM_AgentsTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_EndUserTable LiteLLM_EndUserTable_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_EndUserTable"
    ADD CONSTRAINT "LiteLLM_EndUserTable_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_EndUserTable LiteLLM_EndUserTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_EndUserTable"
    ADD CONSTRAINT "LiteLLM_EndUserTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_InvitationLink LiteLLM_InvitationLink_created_by_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_InvitationLink"
    ADD CONSTRAINT "LiteLLM_InvitationLink_created_by_fkey" FOREIGN KEY (created_by) REFERENCES litellm."LiteLLM_UserTable"(user_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_InvitationLink LiteLLM_InvitationLink_updated_by_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_InvitationLink"
    ADD CONSTRAINT "LiteLLM_InvitationLink_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES litellm."LiteLLM_UserTable"(user_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_InvitationLink LiteLLM_InvitationLink_user_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_InvitationLink"
    ADD CONSTRAINT "LiteLLM_InvitationLink_user_id_fkey" FOREIGN KEY (user_id) REFERENCES litellm."LiteLLM_UserTable"(user_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_JWTKeyMapping LiteLLM_JWTKeyMapping_token_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_JWTKeyMapping"
    ADD CONSTRAINT "LiteLLM_JWTKeyMapping_token_fkey" FOREIGN KEY (token) REFERENCES litellm."LiteLLM_VerificationToken"(token) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_OrganizationMembership LiteLLM_OrganizationMembership_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationMembership"
    ADD CONSTRAINT "LiteLLM_OrganizationMembership_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_OrganizationMembership LiteLLM_OrganizationMembership_organization_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationMembership"
    ADD CONSTRAINT "LiteLLM_OrganizationMembership_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES litellm."LiteLLM_OrganizationTable"(organization_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_OrganizationMembership LiteLLM_OrganizationMembership_user_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationMembership"
    ADD CONSTRAINT "LiteLLM_OrganizationMembership_user_id_fkey" FOREIGN KEY (user_id) REFERENCES litellm."LiteLLM_UserTable"(user_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_OrganizationTable LiteLLM_OrganizationTable_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationTable"
    ADD CONSTRAINT "LiteLLM_OrganizationTable_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_OrganizationTable LiteLLM_OrganizationTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_OrganizationTable"
    ADD CONSTRAINT "LiteLLM_OrganizationTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_ProjectTable LiteLLM_ProjectTable_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ProjectTable"
    ADD CONSTRAINT "LiteLLM_ProjectTable_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_ProjectTable LiteLLM_ProjectTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ProjectTable"
    ADD CONSTRAINT "LiteLLM_ProjectTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_ProjectTable LiteLLM_ProjectTable_team_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_ProjectTable"
    ADD CONSTRAINT "LiteLLM_ProjectTable_team_id_fkey" FOREIGN KEY (team_id) REFERENCES litellm."LiteLLM_TeamTable"(team_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_TagTable LiteLLM_TagTable_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TagTable"
    ADD CONSTRAINT "LiteLLM_TagTable_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_TeamMembership LiteLLM_TeamMembership_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamMembership"
    ADD CONSTRAINT "LiteLLM_TeamMembership_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_TeamTable LiteLLM_TeamTable_model_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamTable"
    ADD CONSTRAINT "LiteLLM_TeamTable_model_id_fkey" FOREIGN KEY (model_id) REFERENCES litellm."LiteLLM_ModelTable"(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_TeamTable LiteLLM_TeamTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamTable"
    ADD CONSTRAINT "LiteLLM_TeamTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_TeamTable LiteLLM_TeamTable_organization_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_TeamTable"
    ADD CONSTRAINT "LiteLLM_TeamTable_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES litellm."LiteLLM_OrganizationTable"(organization_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_UserTable LiteLLM_UserTable_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_UserTable"
    ADD CONSTRAINT "LiteLLM_UserTable_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_UserTable LiteLLM_UserTable_organization_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_UserTable"
    ADD CONSTRAINT "LiteLLM_UserTable_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES litellm."LiteLLM_OrganizationTable"(organization_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_VerificationToken LiteLLM_VerificationToken_budget_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_VerificationToken"
    ADD CONSTRAINT "LiteLLM_VerificationToken_budget_id_fkey" FOREIGN KEY (budget_id) REFERENCES litellm."LiteLLM_BudgetTable"(budget_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_VerificationToken LiteLLM_VerificationToken_object_permission_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_VerificationToken"
    ADD CONSTRAINT "LiteLLM_VerificationToken_object_permission_id_fkey" FOREIGN KEY (object_permission_id) REFERENCES litellm."LiteLLM_ObjectPermissionTable"(object_permission_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_VerificationToken LiteLLM_VerificationToken_organization_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_VerificationToken"
    ADD CONSTRAINT "LiteLLM_VerificationToken_organization_id_fkey" FOREIGN KEY (organization_id) REFERENCES litellm."LiteLLM_OrganizationTable"(organization_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_VerificationToken LiteLLM_VerificationToken_project_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_VerificationToken"
    ADD CONSTRAINT "LiteLLM_VerificationToken_project_id_fkey" FOREIGN KEY (project_id) REFERENCES litellm."LiteLLM_ProjectTable"(project_id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: LiteLLM_WorkflowEvent LiteLLM_WorkflowEvent_run_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_WorkflowEvent"
    ADD CONSTRAINT "LiteLLM_WorkflowEvent_run_id_fkey" FOREIGN KEY (run_id) REFERENCES litellm."LiteLLM_WorkflowRun"(run_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: LiteLLM_WorkflowMessage LiteLLM_WorkflowMessage_run_id_fkey; Type: FK CONSTRAINT; Schema: litellm; Owner: -
--

ALTER TABLE ONLY litellm."LiteLLM_WorkflowMessage"
    ADD CONSTRAINT "LiteLLM_WorkflowMessage_run_id_fkey" FOREIGN KEY (run_id) REFERENCES litellm."LiteLLM_WorkflowRun"(run_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict dbmate


--
-- Dbmate schema migrations
--

INSERT INTO public.schema_migrations (version) VALUES
    ('001');
