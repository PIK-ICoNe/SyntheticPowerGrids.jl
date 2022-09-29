@with_kw mutable struct PGGeneration
    # Per Unit System Definition 
    P_base::Float64 = 100 * 10^6; @assert P_base > 0.0 "Base Power has to be positive."
    V_base::Float64 = 380 * 10^3; @assert V_base > 0.0 "Base Voltage has to be positive."
    Y_base::Float64 = P_base / (V_base)^2;  @assert Y_base > 0.0 "Base Admittance has to be positive."

    # Lines
    coupling::Symbol = :line_lengths
    lines::Symbol = :PiModelLine;
    edge_parameters::Dict = Dict();
    shortest_line_km::Float64 = 0.06; @assert mean_len_km >= 0.0 "The shortest line length can not be negative."
    mean_len_km::Float64 = 37.12856121212121; @assert mean_len_km > 0.0 "The mean line length has to be bigger than 0.0."
    wires_typical::Int64 = 4; @assert wires_typical > 0 "The typical number of wires has to be a positive integer." # Typical number of wires in the german 380kV transmission system
    
    # Nodes
    loads::Symbol = :PQAlgebraic;
    generation_dynamics::Symbol = :DroopControlledInverterApprox;
    num_nodes::Int64; @assert num_nodes > 0.0 "Number of nodes can not be negative."
    nodal_parameters::Dict;
    nodal_shares::Dict; @assert sum(values(nodal_shares)) == 1.0 "The sum of all nodal share has to equal 1.0!"

    # Power 
    # Dict
    power_distribution::Symbol = :Bimodal;
    P0::Float64 = 1.31; @assert maxiters > 0.0 "Reference power for power distribution has to be positive."
    
    # Set Points
    # Todo also use a Dict here
    #set_points = Dict(:P_vec => fill(nothing, num_nodes), :Q_vec => fill(nothing, num_nodes), :V_vec => ones(num_nodes))
    P_vec::Vector = fill(nothing, num_nodes); @assert length(P_vec) == num_nodes "Give a active power set point for each node."
    Q_vec::Vector = fill(nothing, num_nodes); @assert length(Q_vec) == num_nodes "Give a reactive power set point for each node."
    V_vec::Vector{Float64} = ones(num_nodes); @assert length(V_vec) == num_nodes "Give a voltage power set point for each node."

    # Topology
    # use a dict as well ?
    SyntheticNetworksParas::Vector{Float64} = [1, 1/5, 3/10, 1/3, 1/10, 0.0];
    embedded_graph = nothing

    # Miscellaneous
    maxiters::Int64 = 1000; @assert maxiters > 0.0 "Maxiters has to be positive."
    validators::Bool = true
    slack = false
    slack_idx::Int64 = num_nodes
    cables_vec = nothing
    probabilistic_capacity_expansion::Bool = false
    dist_load = nothing
end

function validate_struct(pg_struct::PGGeneration)
    if pg_struct.V_base != 380 * 10^3
        error("This voltage level is not supported. Please use V_base = 380 * 10^3 instead.")
    end

    if pg_struct.loads != :PQAlgebraic
        error("This option for the loads is not supported. Please use loads = :PQAlgebraic instead.")
    end

    if pg_struct.power_distribution != :Bimodal && pg_struct.power_distribution != :Plus_Minus_1
        error("This option for the power distribution is not supported. Please use power_distribution = :Bimodal or :Plus_Minus_1 instead.")
    end

    if pg_struct.power_distribution == :Plus_Minus_1
        if isodd(pg_struct.num_nodes)
            error("If you use the +/-1 Power Distribution you have to use an even number of nodes.")
        end
        
        if pg_struct.slack == true
            error("If you use the +/-1 Power Distribution you can not use a slack.")
        end
    end

    if pg_struct.coupling != :line_lengths && pg_struct.coupling != :homogenous && pg_struct.coupling != :predefined
        error("This option for the coupling is not supported. Please use coupling = :line_lengths, :homogenous or :predefined instead.")
    end

    if pg_struct.generation_dynamics != :DroopControlledInverterApprox && pg_struct.generation_dynamics != :ThirdOrderMachineApprox && pg_struct.generation_dynamics != :Mixed  && pg_struct.generation_dynamics != :SwingEqLVS && pg_struct.generation_dynamics != :dVOCapprox #&& pg_struct.generation_dynamics != :SwingEq
        error("This option for the nodal dynamics is not supported. Please use generation_dynamics = :DroopControlledInverterApprox, :ThirdOrderMachineApprox, :SwingEqLVS, :SwingEq, :dVOCapprox or :Mixed instead.")
    end

    try 
        pg_struct.nodal_shares[:load_share]
    catch err
        error("Please define the share of loads in the network.")
    end

    if pg_struct.generation_dynamics == :ThirdOrderMachineApprox
        try 
            pg_struct.nodal_shares[:ThirdOrderMachineApprox_share]
        catch err
            error("Please define the share of ThirdOrderMachineApprox nodes in the network.")
        end
    end

    if pg_struct.generation_dynamics == :dVOCapprox
        try 
            pg_struct.nodal_shares[:dVOC_share]
        catch err
            error("Please define the share of dVOCapprox nodes in the network.")
        end
    end

    if pg_struct.generation_dynamics == :DroopControlledInverterApprox
        try 
            pg_struct.nodal_shares[:DroopControlledInverterApprox_share]
        catch err
            error("Please define the share of DroopControlledInverterApprox nodes in the network.")
        end
    end

    if pg_struct.generation_dynamics == :Mixed
        try 
            pg_struct.nodal_shares[:ThirdOrderMachineApprox_share]
        catch err
            error("Please define the share of ThirdOrderMachineApprox nodes in the network.")
        end

        try 
            pg_struct.nodal_shares[:DroopControlledInverterApprox_share]
        catch err
            error("Please define the share of DroopControlledInverterApprox nodes in the network.")
        end
    end

    if pg_struct.lines != :StaticLine && pg_struct.lines != :PiModelLine
        error("This option for the line dynamics is not supported. Please use lines = :StaticLine or :PiModelLine instead.")
    end

    if pg_struct.embedded_graph !== nothing
        if typeof(pg_struct.embedded_graph) != EmbeddedGraph{Int64}
            error("If a predefined topology is used please use the EmbeddedGraph structure.")
        end
    end

    if typeof(pg_struct.P_vec) != Vector{Nothing}
        if typeof(pg_struct.P_vec) != Vector{Float64}
            error("Use Vector{Float64} for predefined power vectors.")
        end
    end

    if pg_struct.dist_load !== nothing
        if length(pg_struct.dist_load) != pg_struct.num_nodes
            error("Please give a probability for each nodal set point.")
        end
    end

    if pg_struct.validators == false
       @warn "The validators have been turned off. This option is not advised unless it is for debugging purposes."
    end
end