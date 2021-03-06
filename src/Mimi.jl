module Mimi

using DataStructures
using DataFrames
using Distributions
using NamedArrays
using JSON 
using Electron

export
    ComponentState, run_timestep, run, @defcomp, Model, setindex, addcomponent, setparameter,
    connectparameter, setleftoverparameters, getvariable, adder, MarginalModel, ConnectorCompVector,
    ConnectorCompMatrix, getindex, getdataframe, components, variables, getvpd, unitcheck, plot, getindexcount,
    getindexvalues, getindexlabels, delete!, get_unconnected_parameters, Timestep, isfirsttimestep,
    isfinaltimestep, TimestepVector, TimestepMatrix, hasvalue, update_external_parameter,
    parameters, explore 


import
    Base.getindex, Base.run, Base.show

include("clock.jl")
include("timestep_arrays.jl")
include("mimi-core.jl")
include("metainfo.jl")
include("marginalmodel.jl")
include("adder.jl")
include("connectorcomp.jl")
include("references.jl")
include("plotting.jl")
include("lint_helper.jl")
include("explorer/explore.jl")

end # module
