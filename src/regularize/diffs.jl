#=
diffs.jl
finite differences
2019-03-06 Jeff Fessler, University of Michigan
2020-06 N-D version by Steven Whitaker
=#

export diff_map

using LinearMapsAA: LinearMapAA
using Test: @test, @test_throws


"""
    d = diffnd_forw(X ; dims=1:ndims(X))

N-D finite differences along one or more dimensions,
e.g., for anisotropic TV regularization.
Performs the same operations as
``d = [(I_{N_d} \\otimes \\cdots \\otimes D_{N_1}); \\dots; (D_{N_d} \\otimes \\cdots \\otimes I_{N_1})] X[:]``
where ``D_N`` denotes the `N-1 × N` 1D finite difference matrix
and ``\\otimes`` denotes the Kronecker product,
but does it efficiently
without using `spdiagm` (or any `SparseArrays` function).

Input dimension `N` must exceed 1 for each dimension specified by `dims`,
or must be 1 for all dimensions specified by `dims.`

in
- `X` `N_1 × ... × N_d` array (typically an N-D image).

option
- `dims` dimensions along which to perform finite differences; default `1:d`

out
- `d` vector of length `N_d*...*(N_1-1) + ... + (N_d-1)*...*N_1`
"""
function diffnd_forw(x::AbstractArray{<:Number,D} ; dims=1:D) where {D}
    return reduce(vcat, vec(diff(x, dims = d)) for d in dims)
end


"""
    z =  diffnd_adj(d, N... ; dims=1:length(N), out2d=false)

Adjoint of N-D finite differences along both dimensions.
Performs the same operations as
``z = [(I_{N_d} \\otimes \\cdots \\otimes D_{N_1}); \\dots; (D_{N_d} \\otimes \\cdots \\otimes I_{N_1})]' * d``
where D_N denotes the `N-1 × N` 1D finite difference matrix
and `\\otimes` denotes the Kronecker product,
but does it efficiently without using `spdiagm` (or any `SparseArrays` function).

in
- `d` vector of length `N_d*...*(N_1-1) + ... + (N_d-1)*...*N_1`
- `N...` desired output size

option
- `dims` dimensions along which to perform adjoint finite differences

out
- `z` `prod(N)` vector or `N_1 × ... × N_d` array (typically an N-D image)

"""
function diffnd_adj(d::AbstractVector{<:Number}, N::Vararg{Int,D} ; dims=1:D) where {D}

# todo: diff2d_adj etc. 1-liners for backward compat
# todo: N::Dims instead of Vararg?

    size1 = dim -> (N[1:dim-1]..., N[dim] - 1, N[dim+1:end]...)

    length(d) != sum(prod(size1(dim)) for dim in dims) && throw("length(d)")

    z = zeros(eltype(d), N...)
    for (i, dim) in enumerate(dims)
        if i == 1
            di = @view(d[1:prod(size1(dim))])
        else
            start = 1 + sum(prod(size1(n)) for n in dims[1:i-1])
            len = prod(size1(dim))
            di = @view(d[start:start+len-1])
        end
        di = reshape(di, size1(dim))
        slice1 = selectdim(z, dim, 1)
        slice1 .-= selectdim(di, dim, 1)
        slicen = selectdim(z, dim, 2:N[dim]-1)
        slicen .+= selectdim(di, dim, 1:N[dim]-2) - selectdim(di, dim, 2:N[dim]-1)
        sliceN = selectdim(z, dim, N[dim])
        sliceN .+= selectdim(di, dim, N[dim] - 1)
    end

    return z
end


"""
    T = diffnd_map(N::Int... ; dims=1:length(N))
"""
function diffnd_map(N::Vararg{Int,D} ; dims=1:D) where {D}
    return LinearMapAA(
        x -> diffnd_forw(reshape(x, N...), dims=dims),
        d -> diffnd_adj(d, N..., dims=dims),
        (sum(*(N[1:dim-1]..., N[dim] - 1, N[dim+1:end]...) for dim in dims), prod(N)),
        (name="diffn_map", dims=dims))
end


"""
    T = diff_map(N::Int... ; dims=1:length(N))

in
- `N...` image size

out
- `T` `LinearMapAA` object for regularizing via `T*x`
"""
function diff_map(N::Vararg{Int,D} ; dims=1:D) where {D}
    return diffnd_map(N..., dims=dims)
end


"""
`diff_map(:test)`
self test
"""
function diff_map(test::Symbol)
    test != :test && throw(ArgumentError("test $test"))
    for N in [(2,), (10,), (2,3), (10,11), (1,1,1), (2,3,4), (4,4,4,4)]
        T = diff_map(N...)
        @test Matrix(T)' == Matrix(T')
        @test T.name == "diffn_map"
        T = diff_map(N..., dims=1)
        @test Matrix(T)' == Matrix(T')
        @test T.name == "diffn_map"
        if length(N) >= 2
            for dims in [2, (1,2)]
                T = diff_map(N..., dims=dims)
                @test Matrix(T)' == Matrix(T')
                @test T.name == "diffn_map"
            end
        end
        if length(N) >= 3
            for dims in [3, (1,3), (2,3), (1,2,3)]
                T = diff_map(N..., dims=dims)
                @test Matrix(T)' == Matrix(T')
                @test T.name == "diffn_map"
            end
        end
    end
    # adjoint doesn't work if any of the dimensions specified by dims has size 1
    # (unless all are size 1)
    N = (1,2)
    T = diff_map(N...)
    @test_throws BoundsError Matrix(T)' == Matrix(T')
    T = diff_map(N..., dims = 1)
    @test Matrix(T)' == Matrix(T')
    T = diff_map(N..., dims = 2)
    @test Matrix(T)' == Matrix(T')
    true
end
