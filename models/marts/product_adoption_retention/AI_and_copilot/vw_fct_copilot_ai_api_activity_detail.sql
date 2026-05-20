{{ config(materialized='view') }}

WITH PROD_TENANT_INFO AS
(
    SELECT
        tenant_id,
        tenant_nm,
        account_id,
        data_cntr_cd
    FROM PROD_HARMONIZED.PRODUCT.TENANT_PROF
    WHERE CRNT_RCRD_IND = 'Y'
      AND tenant_typ_nm IN ('PRODUCTION')
      AND organization_typ_nm = 'CUSTOMER'
      AND tenant_enbld_status_nm = 'ENABLED'
            -- remove demo tenants
      AND NOT (
             COALESCE(tenant_nm, '') ILIKE '%sparkcycle%'
          OR COALESCE(tenant_nm, '') ILIKE '%spark cycle%'
          OR COALESCE(tenant_nm, '') ILIKE '%demo%')
),

USER_INFO AS
(
    SELECT
        tenant_dc,
        user_id,

        CASE
            WHEN (
                login_email ILIKE '%@vena%.com'
                OR ntfctn_email ILIKE '%@vena%.com'

                -- admin@ SSO consultant accounts
                OR (
                    last_impersonation_login_dt IS NOT NULL
                    AND admin_access_ind = 'Y'
                    AND login_email ILIKE 'admin@%'
                    AND login_email NOT ILIKE '%@vena%.com'
                )

                OR built_in_admin_accnt = 'Y'
            )
            THEN 'Y'
            ELSE NULL
        END AS consultant_login,

        CASE
            WHEN admin_access_ind = 'Y'
              OR mdlr_access_ind = 'Y'
              OR mngr_access_ind = 'Y'
                THEN 'power user'

            WHEN admin_access_ind = 'N'
             AND mdlr_access_ind = 'N'
             AND mngr_access_ind = 'N'
             AND cntrbtr_access_ind = 'Y'
                THEN 'business user'
        END AS user_type

    FROM PROD_HARMONIZED.PRODUCT.VW_USER_PROF_EML_INCLD
    WHERE crnt_rcrd_ind = 'Y'
),

/* =========================================================
   STANDARD VENA COPILOT PROMPTS
========================================================= */

GENERAL_COPILOT_ACTIVITY AS
(
    SELECT
        api.data_cntr_cd AS vena_hub,
        api.tenant_id,
        CONCAT(api.data_cntr_cd, '.', api.tenant_id) AS vh_tenant_id,
        t.tenant_nm,
        api.user_id,

        u.user_type AS user_license_type,
        u.consultant_login AS is_user_consultant_or_support,

        t.account_id AS salesforce_account_id,

        NULL AS prompt_number,

        request_endpoint_nm AS api_endpoint_name,
        request_method_cd AS post_or_get,

        request_end_dts AS action_timestamp,

        client_context_hdr_nm AS client_context_metadata,

        CASE
            WHEN api.user_agent ILIKE '%teams%'
              OR api.client_context_hdr_nm ILIKE '%teams%'
                THEN 'done through teams'
            ELSE 'done through web client'
        END AS msft_teams_or_web_client,

        CASE
            WHEN api.request_method_cd = 'GET'
             AND api.request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/'
                THEN 'report generation message'

            WHEN api.request_method_cd = 'POST'
             AND api.request_endpoint_nm = '/api/ai/topics/'
                THEN 'AI model creation'

            ELSE 'prompting/question'
        END AS interaction_type,

        CASE
            WHEN api.request_method_cd = 'GET'
             AND api.request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/'
                THEN 'reporting agent'

            WHEN (api.client_context_hdr_nm ILIKE '%mql_agent%' or api.client_context_hdr_nm ILIKE '%query%')
             AND api.request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/chat/'
                THEN 'MQL agent prompt'

            WHEN api.client_context_hdr_nm ILIKE '%planning_agent%'
             AND api.request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/chat/'
                THEN 'Planning agent prompt'

            ELSE 'insights agent'
        END AS copilot_agent_type,

        1 AS prompt_count,

        NULL AS endpoint_call_count,
        NULL AS first_request_start_dts,
        NULL AS last_request_start_dts,
        NULL AS first_request_end_dts,
        NULL AS last_request_end_dts,
        NULL AS endpoint_call_counts_by_endpoint

    FROM PROD_HARMONIZED.PRODUCT.USER_API_ACTIVITY api

    INNER JOIN PROD_TENANT_INFO t
        ON t.tenant_id = api.tenant_id
       AND t.data_cntr_cd = api.data_cntr_cd

    LEFT JOIN USER_INFO u
        ON CONCAT(api.data_cntr_cd, '.', api.tenant_id) = u.tenant_dc
       AND api.user_id = u.user_id

    WHERE TO_DATE(api.request_end_dts) > '2024-02-01'

      AND (
            api.request_endpoint_nm ILIKE '%api/ai/topics/{p}/conversations/{p}/chat/%'

            OR (
                api.request_method_cd = 'GET'
                AND api.request_endpoint_nm = '/api/ai/topics/{p}/conversations/{p}/messages/{p}/templateAdhoc/'
            )

            OR (
                api.request_method_cd = 'POST'
                AND api.request_endpoint_nm = '/api/ai/topics/'
            )
      )

      AND api.user_imprsntd_ind = 'N'
      AND api.request_status_cd = '200'

      -- remove consultants / support users
      AND u.consultant_login IS NULL
),

/* =========================================================
   MCP RAW API CALLS
========================================================= */

MCP_BASE_API AS
(
    SELECT
        t.tenant_nm,
        t.account_id,

        api.tenant_id,
        api.data_cntr_cd,
        api.user_id,

        api.request_start_dts,
        api.request_end_dts,

        api.request_endpoint_nm,
        api.request_method_cd,
        api.request_status_cd,

        api.user_agent,
        api.client_context_hdr_nm,

        api.user_imprsntd_ind

    FROM PROD_HARMONIZED.PRODUCT.USER_API_ACTIVITY api

    INNER JOIN PROD_TENANT_INFO t
        ON t.data_cntr_cd = api.data_cntr_cd
       AND t.tenant_id = api.tenant_id

    LEFT JOIN USER_INFO u
        ON CONCAT(api.data_cntr_cd, '.', api.tenant_id) = u.tenant_dc
       AND api.user_id = u.user_id

    WHERE api.request_end_dts >= '2026-02-01'::TIMESTAMP
      AND api.request_endpoint_nm ILIKE '%internal/mcp%'
      AND api.user_imprsntd_ind = 'N'
      AND api.request_status_cd = '200'

      -- remove consultants / support users
      AND u.consultant_login IS NULL
),

/* =========================================================
   MCP TIMESTAMP GAPS
========================================================= */

MCP_GAPS AS
(
    SELECT
        *,

        LAG(request_start_dts) OVER (
            PARTITION BY data_cntr_cd, tenant_id, user_id
            ORDER BY request_start_dts
        ) AS prev_request_start_dts

    FROM MCP_BASE_API
),

/* =========================================================
   MCP ISLAND DETECTION
========================================================= */

MCP_ISLANDS AS
(
    SELECT
        *,

        CASE
            WHEN prev_request_start_dts IS NULL THEN 1

            WHEN DATEDIFF(
                    millisecond,
                    prev_request_start_dts,
                    request_start_dts
                 ) / 1000.0 > 5
                THEN 1

            ELSE 0
        END AS new_prompt_flag

    FROM MCP_GAPS
),

/* =========================================================
   LABEL EACH MCP PROMPT CLUSTER
========================================================= */

MCP_LABELED AS
(
    SELECT
        *,

        SUM(new_prompt_flag) OVER (
            PARTITION BY data_cntr_cd, tenant_id, user_id
            ORDER BY request_start_dts
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS prompt_number

    FROM MCP_ISLANDS
),

/* =========================================================
   MCP PROMPT CLUSTER SUMMARY
========================================================= */

MCP_CLUSTER_BASE AS
(
    SELECT
        data_cntr_cd,
        tenant_id,
        tenant_nm,
        account_id,
        user_id,

        prompt_number,

        MIN(request_start_dts) AS first_request_start_dts,
        MAX(request_start_dts) AS last_request_start_dts,

        MIN(request_end_dts) AS first_request_end_dts,
        MAX(request_end_dts) AS last_request_end_dts,

        COUNT(*) AS endpoint_call_count,

        MIN(user_agent) AS user_agent,
        MIN(client_context_hdr_nm) AS client_context_hdr_nm

    FROM MCP_LABELED

    GROUP BY
        data_cntr_cd,
        tenant_id,
        tenant_nm,
        account_id,
        user_id,
        prompt_number
),

/* =========================================================
   MCP ENDPOINT COUNTS
========================================================= */

MCP_ENDPOINT_COUNTS AS
(
    SELECT
        data_cntr_cd,
        tenant_id,
        user_id,
        prompt_number,

        request_endpoint_nm,

        COUNT(*) AS endpoint_count

    FROM MCP_LABELED

    GROUP BY
        data_cntr_cd,
        tenant_id,
        user_id,
        prompt_number,
        request_endpoint_nm
),

/* =========================================================
   MCP ENDPOINT COUNTS OBJECT
========================================================= */

MCP_ENDPOINT_COUNTS_OBJECT AS
(
    SELECT
        data_cntr_cd,
        tenant_id,
        user_id,
        prompt_number,

        OBJECT_AGG(
            request_endpoint_nm,
            endpoint_count
        ) AS endpoint_call_counts_by_endpoint

    FROM MCP_ENDPOINT_COUNTS

    GROUP BY
        data_cntr_cd,
        tenant_id,
        user_id,
        prompt_number
),

/* =========================================================
   ONE ROW = ONE ESTIMATED MCP PROMPT
========================================================= */

MCP_PROMPT_ACTIVITY AS
(
    SELECT
        c.data_cntr_cd AS vena_hub,

        c.tenant_id,

        CONCAT(c.data_cntr_cd, '.', c.tenant_id) AS vh_tenant_id,

        c.tenant_nm,

        c.user_id,

        u.user_type AS user_license_type,

        u.consultant_login AS is_user_consultant_or_support,

        c.account_id AS salesforce_account_id,

        c.prompt_number,

        'internal/mcp estimated prompt cluster' AS api_endpoint_name,

        NULL AS post_or_get,

        c.last_request_end_dts AS action_timestamp,

        c.client_context_hdr_nm AS client_context_metadata,

        CASE
            WHEN c.user_agent ILIKE '%teams%'
              OR c.client_context_hdr_nm ILIKE '%teams%'
                THEN 'done through teams'
            ELSE 'done through web client'
        END AS msft_teams_or_web_client,

        'prompting/question' AS interaction_type,

        'MCP server' AS copilot_agent_type,

        1 AS prompt_count,

        c.endpoint_call_count,

        c.first_request_start_dts,
        c.last_request_start_dts,

        c.first_request_end_dts,
        c.last_request_end_dts,

        o.endpoint_call_counts_by_endpoint

    FROM MCP_CLUSTER_BASE c

    LEFT JOIN MCP_ENDPOINT_COUNTS_OBJECT o
        ON  c.data_cntr_cd = o.data_cntr_cd
        AND c.tenant_id = o.tenant_id
        AND c.user_id = o.user_id
        AND c.prompt_number = o.prompt_number

    LEFT JOIN USER_INFO u
        ON CONCAT(c.data_cntr_cd, '.', c.tenant_id) = u.tenant_dc
       AND c.user_id = u.user_id
)

/* =========================================================
   FINAL OUTPUT
========================================================= */

SELECT *
FROM GENERAL_COPILOT_ACTIVITY

UNION ALL

SELECT *
FROM MCP_PROMPT_ACTIVITY

ORDER BY
    vena_hub,
    tenant_nm,
    user_id,
    action_timestamp