{{ config(materialized='view') }}

SELECT
    LAST_DAY(action_timestamp::DATE) AS end_of_month,

    COUNT(DISTINCT vh_tenant_id) AS unique_tenant_count,

    COUNT(DISTINCT CONCAT(vh_tenant_id, '.', user_id)) AS unique_customer_users,

    COUNT_IF(interaction_type = 'prompting/question') AS no_of_questions_asked,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'Planning agent prompt'
    ) AS no_of_planning_agent_prompts,

       COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'MQL agent prompt'
    ) AS no_of_query_agent_prompts,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'MCP server'
    ) AS no_of_mcp_prompts,

    COUNT_IF(  copilot_agent_type = 'reporting agent'
    ) AS no_of_reporting_agent_prompts,

    COUNT_IF(
        interaction_type = 'prompting/question'
        AND copilot_agent_type = 'insights agent'
    )
    -
    COUNT_IF(
        copilot_agent_type = 'reporting agent'
    ) AS no_of_analytics_agent_prompts

FROM {{ ref('vw_fct_copilot_ai_api_activity_detail') }}

WHERE action_timestamp IS NOT NULL

GROUP BY
    LAST_DAY(action_timestamp::DATE)

ORDER BY
    end_of_month