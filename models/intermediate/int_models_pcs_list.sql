{{ config(materialized = 'table') }}

with pcs_model_ids as (

    select model_id
    from values
        ('651628815408562176'),
        ('941816194549940225'),
        ('1407901556913209344'),
        ('941816307460472833'),
        ('1406002651013054464'),
        ('949104660089012224'),
        ('949104737973043200'),
        ('949104806889652224'),
        ('991853638275694592'),
        ('1433199543478910976'),
        ('969369227084824577'),
        ('864937233935892481'),
        ('1012900181447147520'),
        ('1406395748766973952'),
        ('1007057562749894656')
    as t(model_id)

),

latest_models as (

    select
        id as model_id,
        datacenter,
        tenant_id,
        concat(datacenter, '.', tenant_id) as vh_tenant_id,
        model_name,
        etl_load_date
    from {{ source('mtserver', 'mtserver_models_staging') }}
    qualify row_number() over (
        partition by datacenter, tenant_id, id
        order by etl_load_date desc
    ) = 1

),

pcs_model_mapping as (

    select
        m.vh_tenant_id,
        m.tenant_id,
        m.datacenter,
        m.model_id,
        m.model_name,

        iff(p.model_id is not null, true, false) as pcs_boolean,

        case
            when p.model_id is not null then 'TRUE'
            else 'FALSE'
        end as pcs_model_status,

        m.etl_load_date

    from latest_models m
    left join pcs_model_ids p
        on m.model_id = p.model_id

)

select *
from pcs_model_mapping