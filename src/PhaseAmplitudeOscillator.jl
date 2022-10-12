using NetworkDynamics: ODEVertex
import PowerDynamics: dimension, symbolsof, construct_vertex 
import PowerDynamics: showdefinition

function parameter_DroopControlledInverterApprox(;P_set, Q_set, τ_P, τ_Q, K_P, K_Q, V_r, Y_n)
    P = P_set
    Q = Q_set
    V = V_r
    Bᵤ = 1im 
    Cᵤ = - 1 / (2 * τ_Q * V_r^2)
    Gᵤ = 0
    Hᵤ = - K_Q / (τ_Q * V_r)
    Bₓ = - 1 / τ_P
    Cₓ = 0
    Gₓ = - K_P / τ_P
    Hₓ = 0 
    x_dims = 1

    return [P, Q, V, Bᵤ, Cᵤ, Gᵤ, Hᵤ, Bₓ, Cₓ, Gₓ, Hₓ, Y_n, x_dims]
end

function parameter_ThirdOrderMachineApprox(;P_set, Q_set, E_f, E_set, X, α, γ, Y_n)
    P = P_set
    Q = Q_set
    V = E_set
    Bᵤ = 1im
    Cᵤ = (- E_f / (2E_set^3)) / α
    Gᵤ = 0.0
    Hᵤ = - X / (α * (E_set)^2)
    Bₓ = - γ
    Cₓ = 0.0 
    Gₓ = -1
    Hₓ = 0
    x_dims = 1

    return [P, Q, V, Bᵤ, Cᵤ, Gᵤ, Hᵤ, Bₓ, Cₓ, Gₓ, Hₓ, Y_n, x_dims]
end

function parameter_dVOC(;P_set, Q_set, V_set, η, α, κ, Y_n)
    P = P_set
    Q = Q_set
    V = V_set
    Bᵤ = nothing
    Cᵤ = - α * η / (V_set^2) + η * exp(κ * 1im) * complex(P_set, - Q_set) / (V_set^4)
    Gᵤ = - η * exp(κ * 1im) / (V_set^2)
    Hᵤ = 1im * η * exp(κ * 1im) / (V_set^2)
    Bₓ = nothing
    Cₓ = nothing
    Gₓ = nothing
    Hₓ = nothing
    x_dims = 0

    return [P, Q, V, Bᵤ, Cᵤ, Gᵤ, Hᵤ, Bₓ, Cₓ, Gₓ, Hₓ, Y_n, x_dims]
end

struct NormalForm <: AbstractNode
    P
    Q
    V
    Bᵤ
    Cᵤ
    Gᵤ
    Hᵤ
    Bₓ
    Cₓ
    Gₓ
    Hₓ
    Y_n    # Shunt admittance for power dynamics
    x_dims # Dimension of the internal variables
end

NormalForm(; P, Q, V, Bᵤ, Cᵤ, Gᵤ, Hᵤ, Bₓ, Cₓ, Gₓ, Hₓ, Y_n = 0, x_dims) = NormalForm(P, Q, V, Bᵤ, Cᵤ, Gᵤ, Hᵤ, Bₓ, Cₓ, Gₓ, Hₓ, Y_n, x_dims)

function construct_vertex(nf::NormalForm)
    @assert isreal(nf.x_dims)  "The dimension of x has to be a real number!"
    @assert isinteger(real(nf.x_dims)) "The dimension of x has to be a an integer!"
    @assert real(nf.x_dims) >= 0 "The dimension of x can not be negative!"
    x_dims = Int64(real(nf.x_dims))

    sym = symbolsof(nf)
    dim = dimension(nf)
    mass_matrix = ones(Int64, dim, dim) |> Diagonal

    P = nf.P
    Q = nf.Q
    V = nf.V
    
    Bᵤ = nf.Bᵤ
    Cᵤ = nf.Cᵤ
    Gᵤ = nf.Gᵤ
    Hᵤ = nf.Hᵤ
    
    Bₓ = nf.Bₓ
    Cₓ = nf.Cₓ
    Gₓ = nf.Gₓ
    Hₓ = nf.Hₓ

    Y_n = nf.Y_n

    if x_dims == 1  # Special case of a single internal variable

        @assert length(Bₓ) == x_dims "Bₓ parameters have the wrong dimension."
        @assert length(Cₓ) == x_dims "Cₓ parameters have the wrong dimension."
        @assert length(Gₓ) == x_dims "Gₓ parameters have the wrong dimension."
        @assert length(Hₓ) == x_dims "Hₓ parameters have the wrong dimension."

        rhs! = function (dz, z, edges, p, t)
            i = total_current(edges) + Y_n * (z[1] + z[2] * 1im) # Current, couples the NF to the rest of the network, Y_n Shunt admittance
            u = z[1] + z[2] * im  # Complex Voltage
            x = z[3]              # Internal Variable  
            s = u * conj(i)       # Apparent Power S = P + iQ
            δp = real(s) - P      # active power deviation
            δq = imag(s) - Q      # reactive power deviation
            δv2 = abs2(u) - V^2 # Absolute squared voltage deviation

        
            dx = (Bₓ .* x + Cₓ .* δv2 + Gₓ .* δp + Hₓ .* δq)
            du = (Bᵤ  * x + Cᵤ  * δv2 + Gᵤ  * δp + Hᵤ  * δq) * u
            
            # Splitting the complex parameters
            dz[1] = real(du)  
            dz[2] = imag(du)
            dz[3] = real(dx)          

            return nothing
        end
    elseif x_dims == 0  # Special case of no internal variable

        rhs! = function (dz, z, edges, p, t)
            i = total_current(edges) + Y_n * (z[1] + z[2] * 1im) # Current, couples the NF to the rest of the network, Y_n Shunt admittance
            u = z[1] + z[2] * im  # Complex Voltage
            s = u * conj(i)       # Apparent Power S = P + iQ
            δp = real(s) - P      # active power deviation
            δq = imag(s) - Q      # reactive power deviation
            δv2 = abs2(u) - V^2 # Absolute squared voltage deviation

            du = (Cᵤ * δv2 + Gᵤ * δp + Hᵤ * δq) * u
            
            # Splitting the complex parameters
            dz[1] = real(du)  
            dz[2] = imag(du)
            return nothing
        end
    elseif x_dims > 1 # Case of multiple internal variables
        @assert length(Bₓ) == x_dims "Bₓ parameters have the wrong dimension."
        @assert length(Cₓ) == x_dims "Cₓ parameters have the wrong dimension."
        @assert length(Gₓ) == x_dims "Gₓ parameters have the wrong dimension."
        @assert length(Hₓ) == x_dims "Hₓ parameters have the wrong dimension."
        rhs! = function (dz, z, edges, p, t)
            i = total_current(edges) + Y_n * (z[1] + z[2] * 1im) # Current, couples the NF to the rest of the network, Y_n Shunt admittance
            u = z[1] + z[2] * im  # Complex Voltage
            x = z[3:dim]          # Internal Variables
            s = u * conj(i)       # Apparent Power S = P + iQ
            δp = real(s) - P      # active power deviation
            δq = imag(s) - Q      # reactive power deviation
            δv2 = abs2(u) - V^2 # Absolute squared voltage deviation

        
            dx = (Bₓ .* x + Cₓ .* δv2 + Gₓ .* δp + Hₓ .* δq)
            du = (Bᵤ  * x + Cᵤ  * δv2 + Gᵤ  * δp + Hᵤ  * δq) * u
            
            # Splitting the complex parameters
            dz[1] = real(du)  
            dz[2] = imag(du)
            dz[3:dim] = real(dx)

            return nothing
        end
    end
    ODEVertex(rhs!, dim, mass_matrix, sym)
end

function symbolsof(nf::NormalForm)
    if imag(nf.x_dims) == 0.0
        x_dims = Int64(real(nf.x_dims))
        symbols = [:u_r, :u_i]
        append!(symbols, [Symbol("x_$i") for i in 1:x_dims])

        return symbols
    else
        error("The normal form dimension has to be a real number!")
    end
end

function dimension(nf::NormalForm)
    if imag(nf.x_dims) == 0.0
        x_dims = Int64(real(nf.x_dims))
        return 2 + x_dims
    else
        error("The normal form dimension has to be a real number!")
    end
end

export NormalForm