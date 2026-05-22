
{{ config(materialized = 'view') }}

WITH prod_tenant_info AS
(
    SELECT
        tenant_id,
        tenant_nm,
        account_id,
        data_cntr_cd,
        tenant_enbld_status_nm,
        CONCAT(data_cntr_cd, '.', tenant_id) AS vh_tenant_id
    FROM PROD_HARMONIZED.PRODUCT.TENANT_PROF
    WHERE crnt_rcrd_ind = 'Y'
      AND tenant_typ_nm IN ('PRODUCTION')
      AND organization_typ_nm = 'CUSTOMER'
     AND tenant_enbld_status_nm = 'ENABLED'
      AND NOT (
             COALESCE(tenant_nm, '') ILIKE '%sparkcycle%'
          OR COALESCE(tenant_nm, '') ILIKE '%spark cycle%'
          OR COALESCE(tenant_nm, '') ILIKE '%demo%'
          OR COALESCE(tenant_nm, '') ILIKE '%vena%'
      )
),

user_info AS
(
    SELECT
        tenant_dc,
        user_id,
        copilot_access_ind
    FROM PROD_HARMONIZED.PRODUCT.VW_USER_PROF_EML_INCLD
    WHERE crnt_rcrd_ind = 'Y'
      AND actvtn_status_nm = 'ACTIVE'
),

tenant_copilot_permissions AS
(
    SELECT
        tenant_dc,
        COUNT(DISTINCT user_id) AS num_copilot_permissions_assigned
    FROM user_info
    WHERE copilot_access_ind = 'Y'
    GROUP BY tenant_dc
),

tenant_summary AS
(
    SELECT
        salesforce_account_id AS account_id,
        tenant_id,
        tenant_nm,
        vh_tenant_id,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND not_customer_user = FALSE
        ) AS total_prompts_customer,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND copilot_agent_type = 'insights agent'
            AND not_customer_user = FALSE
        )
        -
        COUNT_IF(
            copilot_agent_type = 'reporting agent'
            AND not_customer_user = FALSE
        ) AS insights_agent_prompts,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND copilot_agent_type = 'MQL agent prompt'
            AND not_customer_user = FALSE
        ) AS mql_agent_prompts,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND copilot_agent_type = 'Planning agent prompt'
            AND not_customer_user = FALSE
        ) AS planning_agent_prompts,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND copilot_agent_type = 'MCP server'
            AND not_customer_user = FALSE
        ) AS mcp_prompts,

        COUNT_IF(
            copilot_agent_type = 'reporting agent'
            AND not_customer_user = FALSE
        ) AS Adhoc_reports_generated,

        COUNT_IF(
            interaction_type = 'prompting/question'
            AND not_customer_user = TRUE
        ) AS total_prompts_by_vena,

        IFF(
            COUNT_IF(
                interaction_type = 'AI model creation'
                AND not_customer_user = FALSE
            ) > 0,
            TRUE,
            FALSE
        ) AS ai_model_user_created,

        FALSE AS ai_model_system_generated

    FROM {{ ref('vw_fct_copilot_ai_api_activity_detail') }}

--    WHERE action_timestamp IS NOT NULL

    GROUP BY
        salesforce_account_id,
        tenant_id,
        tenant_nm,
        vh_tenant_id
),

acct AS
(
    SELECT
        LEFT(account_id, 15) AS account_id,
        account_nm,
        go_live_dt,
        vena_id
    FROM PROD_HARMONIZED.SALES.VW_ACCOUNT_PROF
    WHERE crnt_rcrd_ind = 'Y'
),

ps_projects AS
(
    SELECT
        LEFT(account_id, 15) AS account_id,
        vena_id,
        vena_project_cd,
        project_nm,
        cohort_nm,
        srvcs_dlvrd_nms,
        project_kickoff_dt,
        go_live_dt,
        project_close_dt,
        practice_mngr_nm,
        project_mgr_nm,
        delivered_by_nm,

        IFF(
            project_kickoff_dt < CURRENT_DATE
            AND (go_live_dt IS NULL OR go_live_dt > CURRENT_DATE),
            TRUE,
            FALSE
        ) AS current_implementation,

        ROW_NUMBER() OVER (
            PARTITION BY LEFT(account_id, 15)
            ORDER BY project_kickoff_dt ASC
        ) AS rn_earliest

    FROM PROD_PRESENTATION.PROFESSIONAL_SERVICES.VW_PS_PROJECTS
    WHERE crnt_rcrd_ind = 'Y'
      AND LOWER(cohort_nm) IN ('path', 'path+', 'custom')
      AND project_nm NOT ILIKE '%do not%'
),

coaching AS
(
    SELECT DISTINCT
        vena_project_cd,
        stry_title,
        percentage_complete,
        state,
        due_dt,
        start_dt
    FROM PROD_PRESENTATION.PROFESSIONAL_SERVICES.VW_PROJECT_STORY_INFO
    WHERE deleted_dts IS NULL
      AND (
            (LOWER(stry_title) LIKE '%vena copilot%' OR LOWER(stry_title) LIKE '%copilot%')
        AND (LOWER(stry_title) LIKE '%coaching%' OR LOWER(stry_title) LIKE '%meeting%')
      )
      AND stry_title NOT ILIKE '%include copilot demo%'
      AND vena_project_cd IS NOT NULL
    QUALIFY RANK() OVER (
        PARTITION BY vena_project_cd, stry_id
        ORDER BY updated_dts
    ) = 1
)

SELECT
    p.account_id,
    a.account_nm,
    p.tenant_nm,
    p.tenant_id,
    p.vh_tenant_id,

    COALESCE(a.vena_id, ps.vena_id) AS vena_id,

    ps.project_nm,
    ps.practice_mngr_nm,
    ps.project_mgr_nm,
    ps.delivered_by_nm,
    ps.cohort_nm,
    ps.srvcs_dlvrd_nms,
    ps.project_kickoff_dt,
    ps.go_live_dt AS ps_project_go_live_dt,
    ps.project_close_dt,
    ps.current_implementation,

    c.stry_title,
    c.percentage_complete,
    c.state,
    c.due_dt,
    c.start_dt,

    COALESCE(tcp.num_copilot_permissions_assigned, 0) AS num_copilot_permissions_assigned,

    COALESCE(ts.ai_model_user_created, FALSE) AS ai_model_user_created,
    COALESCE(ts.ai_model_system_generated, FALSE) AS ai_model_system_generated,

    COALESCE(ts.total_prompts_by_vena, 0) AS total_prompts_by_vena,

    COALESCE(ts.total_prompts_customer, 0) AS total_prompts_customer,
    COALESCE(ts.insights_agent_prompts, 0) AS analytics_agent_prompts,
    COALESCE(ts.mql_agent_prompts, 0) AS query_agent_prompts,
    COALESCE(ts.planning_agent_prompts, 0) AS planning_agent_prompts,
    COALESCE(ts.mcp_prompts, 0) AS mcp_prompts,
    COALESCE(ts.Adhoc_reports_generated, 0) AS Adhoc_reports_generated

FROM prod_tenant_info p

LEFT JOIN acct a
    ON LEFT(p.account_id, 15) = a.account_id

LEFT JOIN tenant_summary ts
    ON p.vh_tenant_id = ts.vh_tenant_id

LEFT JOIN tenant_copilot_permissions tcp
    ON p.vh_tenant_id = tcp.tenant_dc

LEFT JOIN ps_projects ps
    ON LEFT(p.account_id, 15) = ps.account_id

LEFT JOIN coaching c
    ON ps.vena_project_cd = c.vena_project_cd

WHERE ps.rn_earliest = 1
   OR ps.rn_earliest IS NULL