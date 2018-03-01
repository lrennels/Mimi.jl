# Create the run_timestep or init function for this component
function _eval_funcs(comp_def::ComponentDef)
    @eval($(run_expr(comp_def)))
    @eval($(init_expr(comp_def)))
end

function _eval_funcs(md::ModelDef)
    if ! funcs_generated(md)
        map(_eval_funcs, compdefs(md))
        set_funcs_generated(md, true)
    end
end

connector_comp_name(i::Int) = Symbol("ConnectorComp$i")

# Return the datatype to use for instance variables/parameters
function _instance_datatype(md::ModelDef, def::DatumDef, start::Int)
    dtype = def.datatype == Number ? number_type(md) : def.datatype
    dims = dimensions(def)
    num_dims = dimcount(def)

    if num_dims == 0
        T = dtype

    elseif dims[1] != :time
        T = Array{dtype, num_dims}
        # return Array{dtype, num_dims}
    
    else
        step = step_size(md)
        ts_type = num_dims == 1 ? TimestepVector : TimestepMatrix
        T = ts_type{dtype, start, step}
        # return ts_type{dtype, start, step}       
    end

    # println("_instance_datatype($def) returning $T")
    return T
end

function _instance_datatype_ref(md::ModelDef, def::DatumDef, start::Int)
    T = _instance_datatype(md::ModelDef, def::DatumDef, start::Int)
    return Ref{T}
end

# Return the parameterized types for parameters and variables for 
# the given component.
function _datum_types(md::ModelDef, comp_def::ComponentDef)
    var_defs = variables(comp_def)
    par_defs = parameters(comp_def)

    start = comp_def.start

    vnames = Tuple([name(vdef) for vdef in var_defs])
    pnames = Tuple([name(pdef) for pdef in par_defs])

    vtypes = Tuple{[_instance_datatype_ref(md, vdef, start) for vdef in var_defs]...}
    ptypes = Tuple{[_instance_datatype_ref(md, pdef, start) for pdef in par_defs]...}

    # println("_datum_types:\n  vtypes=$vtypes\n  ptypes=$ptypes\n")

    vars_type = ComponentInstanceVariables{vnames, vtypes}
    pars_type = ComponentInstanceParameters{pnames, ptypes}
    
    return (vars_type, pars_type)
end

# Create the Ref or Array that will hold the value(s) for a Parameter or Variable
function _instantiate_datum(md::ModelDef, def::DatumDef, start::Int)
    dtype = _instance_datatype(md, def, start)
    dims = dimensions(def)
    num_dims = length(dims)
    
    # println("_instantiate_datum(md, def: $def) : dims: $dims, dtype: $dtype")

    if num_dims == 0
        value = dtype(0)

    elseif dims[1] != :time
        # TODO Handle unnamed indices properly
        dim_counts = [indexcount(md, i) for i in dims]
        value = dtype(dim_counts...)

    elseif num_dims == 1
        value = dtype(indexcount(md, :time))

    else
        value = dtype(indexcount(md, :time), indexcount(md, dims[2]))
    end

    # println("returning Ref{$dtype}($value)\n\n")
    return Ref{dtype}(value)
end

"""
    instantiate_component(md::ModelDef, comp_def::ComponentDef)

Instantiate a component and return the resulting ComponentInstance.
"""
function instantiate_component(md::ModelDef, comp_def::ComponentDef)
    comp_name = name(comp_def)
    start = comp_def.start
    
    (vars_type, pars_type) = _datum_types(md, comp_def)
    
    var_vals = [_instantiate_datum(md, vdef, start) for vdef in variables(comp_def)]
    par_vals = [_instantiate_datum(md, pdef, start) for pdef in parameters(comp_def)]

    # println("instantiate_component:\n  vtype: $vars_type\n\n  ptype: $pars_type\n\n  vvals: $var_vals\n\n  pvals: $par_vals\n\n")

    comp_inst = ComponentInstance(comp_def, vars_type(var_vals), pars_type(par_vals), comp_name)
    return comp_inst
end

"""
    instantiate_components(mi::ModelInstance)

Instantiate all components and add the ComponentInstances to `mi.`
"""
function instantiate_components(mi::ModelInstance)
    md = modeldef(mi)
    
    # loop over components, including new ConnectorComps, in order.
    for comp_def in compdefs(md)
        comp_inst = instantiate_component(md, comp_def)
        addcomponent(mi, comp_inst)
    end
    return nothing
end

function build(m::Model)
    println("Building model...")

    # Reference a copy in the ModelInstance to avoid changes underfoot
    m.mi = build(copy(m.md))

    return m.mi
end

function build(md::ModelDef)
    # check if all parameters are set
    not_set = unconnected_params(md)
    if ! isempty(not_set)
        msg = "Cannot build model; the following parameters are not set: "
        for p in not_set
            msg = string(msg, p, " ")
        end
        error(msg)
    end

    _eval_funcs(md)

    mi = ModelInstance(md)
    instantiate_components(mi)

    comps = mi.components
    backups = md.backups

    # Make the internal parameter connections, including hidden connections between ConnectorComps.
    for ipc in internal_param_conns(md)
        # println("ipc: $ipc")
        src_comp_inst = comps[ipc.src_comp_name]
        dst_comp_inst = comps[ipc.dst_comp_name]
        value = get_variable_value(src_comp_inst, ipc.src_var_name)
        set_parameter_value(dst_comp_inst, ipc.dst_par_name, value)
    end

    # Make the external parameter connections.
    for ext in external_param_conns(md)
        param = external_param(md, ext.external_param)
        comp = comps[ext.comp_name]
        set_parameter_value(comp, ext.param_name, value(param))
    end

    # Make the external parameter connections for the hidden ConnectorComps: connect each :input2 to its associated backup value.
    for i in 1:length(backups)
        comp_name = connector_comp_name(i)
        param = external_param(md, backups[i])
        comp_inst = comps[comp_name]
        set_parameter_value(comp_inst, :input2, value(param))
    end

    return mi
end