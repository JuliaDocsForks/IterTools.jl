__precompile__()

module IterTools

import Base.Iterators: drop, take

import Base: start, next, done, iterate, eltype, length, size, peek
import Base: tail
import Base: IteratorSize, IteratorEltype
import Base: SizeUnknown, IsInfinite, HasLength, HasShape
import Base: HasEltype, EltypeUnknown

export
    takestrict,
    repeatedly,
    chain,
    product,
    distinct,
    partition,
    groupby,
    imap,
    subsets,
    iterated,
    nth,
    takenth,
    peekiter,
    peek,
    ncycle

function has_length(it)
    it_size = IteratorSize(it)

    return isa(it_size, HasLength) || isa(it_size, HasShape)
end

promote_iteratoreltype(::HasEltype, ::HasEltype) = HasEltype()
promote_iteratoreltype(::IteratorEltype, ::IteratorEltype) = EltypeUnknown()

# return the size for methods depending on the longest iterator
longest(::T, ::T) where {T<:IteratorSize} = T()
function longest(::S, ::T) where {T<:IteratorSize, S<:IteratorSize}
    longest(T(), S())
end
longest(::HasShape, ::HasShape) = HasLength()
longest(::HasLength, ::HasShape) = HasLength()
longest(::SizeUnknown, ::HasShape) = SizeUnknown()
longest(::SizeUnknown, ::HasLength) = SizeUnknown()
longest(::IsInfinite, ::HasShape) = IsInfinite()
longest(::IsInfinite, ::HasLength) = IsInfinite()
longest(::IsInfinite, ::SizeUnknown) = IsInfinite()

# return the size for methods depending on the shortest iterator
shortest(::T, ::T) where {T<:IteratorSize} = T()
function shortest(::S, ::T) where {T<:IteratorSize, S<:IteratorSize}
    shortest(T(), S())
end
shortest(::HasShape, ::HasShape) = HasLength()
shortest(::HasLength, ::HasShape) = HasLength()
shortest(::IsInfinite, ::HasShape) = HasLength()
shortest(::IsInfinite, ::HasLength) = HasLength()
shortest(::SizeUnknown, ::HasShape) = SizeUnknown()
shortest(::SizeUnknown, ::HasLength) = SizeUnknown()
shortest(::SizeUnknown, ::IsInfinite) = SizeUnknown()

include("tuple_types.jl")

# Iterate through the first n elements, throwing an exception if
# fewer than n items ar encountered.

struct TakeStrict{I}
    xs::I
    n::Int
end
IteratorSize(::Type{<:TakeStrict}) = HasLength()
IteratorEltype(::Type{TakeStrict{I}}) where {I} = IteratorEltype(I)
eltype(::Type{TakeStrict{I}}) where {I} = eltype(I)

"""
    takestrict(xs, n::Int)

Like `take()`, an iterator that generates at most the first `n` elements of `xs`, but throws
an exception if fewer than `n` items are encountered in `xs`.

```jldoctest
julia> a = :1:2:11
1:2:11

julia> collect(takestrict(a, 3))
3-element Array{Int64,1}:
 1
 3
 5
```
"""
takestrict(xs, n::Int) = TakeStrict(xs, n)

function iterate(it::TakeStrict, state=(it.n,))
    n, xs_state = first(state), tail(state)
    n <= 0 && return nothing
    xs_iter = iterate(it.xs, xs_state...)

    if xs_iter === nothing
        throw(ArgumentError("In takestrict(xs, n), xs had fewer than n items to take."))
    end

    v, xs_state = xs_iter
    return v, (n - 1, xs_state)
end

length(it::TakeStrict) = it.n


# Repeat a function application n (or infinitely many) times.

struct RepeatCall{F<:Base.Callable}
    f::F
    n::Int
end
IteratorSize(::Type{<:RepeatCall}) = HasLength()
IteratorEltype(::Type{<:RepeatCall}) = EltypeUnknown()
length(it::RepeatCall) = it.n

"""
    repeatedly(f)
    repeatedly(f, n)

Call function `f` `n` times, or infinitely if `n` is omitted.

```julia
julia> t() = (sleep(0.1); Dates.millisecond(now()))
t (generic function with 1 method)

julia> collect(repeatedly(t, 5))
5-element Array{Any,1}:
 993
  97
 200
 303
 408
```
"""
repeatedly(f, n) = RepeatCall(f, n)
iterate(it::RepeatCall, state=it.n) = state <= 0 ? nothing : (it.f(), state - 1)

struct RepeatCallForever{F<:Base.Callable}
    f::F
end
IteratorSize(::Type{<:RepeatCallForever}) = IsInfinite()
IteratorEltype(::Type{<:RepeatCallForever}) = EltypeUnknown()

repeatedly(f) = RepeatCallForever(f)
iterate(it::RepeatCallForever, state=nothing) = (it.f(), nothing)


# Concatenate the output of n iterators
struct Chain{T<:Tuple}
    xss::T
end


"""
    chain(xs...)

Iterate through any number of iterators in sequence.

```jldoctest
julia> for i in chain(1:3, ['a', 'b', 'c'])
           @show i
       end
i = 1
i = 2
i = 3
i = 'a'
i = 'b'
i = 'c'
```
"""
chain(xss...) = Chain(xss)

length(it::Chain{Tuple{}}) = 0
length(it::Chain) = sum(length, it.xss)
function IteratorEltype(::Type{Chain{T}}) where T
    mapreduce_tt(IteratorEltype, promote_iteratoreltype, HasEltype(), T)
end
function IteratorSize(::Type{Chain{T}}) where T
    mapreduce_tt(IteratorSize, longest, HasLength(), T)
end
eltype(::Type{Chain{T}}) where {T} = mapreduce_tt(eltype, typejoin, Union{}, T)

function start(it::Chain)
    i = 1
    xs_state = nothing
    while i <= length(it.xss)
        xs_state = start(it.xss[i])
        if !done(it.xss[i], xs_state)
            break
        end
        i += 1
    end
    return i, xs_state
end

function next(it::Chain, state)
    i, xs_state = state
    v, xs_state = next(it.xss[i], xs_state)
    while done(it.xss[i], xs_state)
        i += 1
        if i > length(it.xss)
            break
        end
        xs_state = start(it.xss[i])
    end
    return v, (i, xs_state)
end

done(it::Chain, state) = state[1] > length(it.xss)


# Cartesian product as a sequence of tuples

struct Product{T<:Tuple}
    xss::T
end

function IteratorSize(::Type{Product{T}}) where T
    mapreduce_tt(IteratorSize, longest, HasLength(), T)
end
eltype(::Type{Product{T}}) where {T} = map_tt_t(eltype, T)
length(p::Product) = mapreduce(length, *, 1, p.xss)

"""
    product(xs...)

Iterate over all combinations in the Cartesian product of the inputs.

```jldoctest
julia> for p in product(1:3,4:5)
           @show p
       end
p = (1, 4)
p = (2, 4)
p = (3, 4)
p = (1, 5)
p = (2, 5)
p = (3, 5)
```
"""
product(xss...) = Product(xss)

function start(it::Product)
    n = length(it.xss)
    js = Any[start(xs) for xs in it.xss]
    for i = 1:n
        if done(it.xss[i], js[i])
            return js, nothing
        end
    end
    vs = Vector{Any}(undef, n)
    for i = 1:n
        vs[i], js[i] = next(it.xss[i], js[i])
    end
    return js, vs
end

function next(it::Product, state)
    js = copy(state[1])
    vs = copy(state[2])
    ans = tuple(vs...)

    n = length(it.xss)
    for i in 1:n
        if !done(it.xss[i], js[i])
            vs[i], js[i] = next(it.xss[i], js[i])
            return ans, (js, vs)
        end

        js[i] = start(it.xss[i])
        vs[i], js[i] = next(it.xss[i], js[i])
    end
    ans, (js, nothing)
end

done(it::Product, state) = state[2] === nothing


# Filter out reccuring elements.

struct Distinct{I, J}
    xs::I

    # Map elements to the index at which it was first seen, so given an iterator
    # state (index) we can test if an element has previously been observed.
    seen::Dict{J, Int}
end

IteratorSize(::Type{<:Distinct}) = SizeUnknown()

eltype(::Type{Distinct{I, J}}) where {I, J} = J

"""
    distinct(xs)

Iterate through values skipping over those already encountered.

```jldoctest
julia> for i in distinct([1,1,2,1,2,4,1,2,3,4])
           @show i
       end
i = 1
i = 2
i = 4
i = 3
```
"""
distinct(xs::I) where {I} = Distinct{I, eltype(xs)}(xs, Dict{eltype(xs), Int}())

function iterate(it::Distinct, state=(1,))
    idx, xs_state = first(state), tail(state)
    xs_iter = iterate(it.xs, xs_state...)

    while xs_iter !== nothing
        val, xs_state = xs_iter
        get!(it.seen, val, idx) >= idx && return (val, (idx + 1, xs_state))

        xs_iter = iterate(it.xs, xs_state)
        idx += 1
    end

    return nothing
end


# Group output from at iterator into tuples.
# E.g.,
#   partition(count(1), 2) = (1,2), (3,4), (5,6) ...
#   partition(count(1), 2, 1) = (1,2), (2,3), (3,4) ...
#   partition(count(1), 2, 3) = (1,2), (4,5), (7,8) ...

struct Partition{I, N}
    xs::I
    step::Int
end
IteratorSize(::Type{<:Partition}) = SizeUnknown()

eltype(::Type{Partition{I, N}}) where {I, N} = NTuple{N, eltype(I)}

"""
    partition(xs, n, [step])

Group values into `n`-tuples.

```jldoctest
julia> for i in partition(1:9, 3)
           @show i
       end
i = (1, 2, 3)
i = (4, 5, 6)
i = (7, 8, 9)
```

If the `step` parameter is set, each tuple is separated by `step` values.

```jldoctest
julia> for i in partition(1:9, 3, 2)
           @show i
       end
i = (1, 2, 3)
i = (3, 4, 5)
i = (5, 6, 7)
i = (7, 8, 9)

julia> for i in partition(1:9, 3, 3)
           @show i
       end
i = (1, 2, 3)
i = (4, 5, 6)
i = (7, 8, 9)

julia> for i in partition(1:9, 2, 3)
           @show i
       end
i = (1, 2)
i = (4, 5)
i = (7, 8)
```
"""
function partition(xs::I, n::Int) where I
    Partition{I, n}(xs, n)
end

function partition(xs::I, n::Int, step::Int) where I
    if step < 1
        throw(ArgumentError("Partition step must be at least 1."))
    end

    Partition{I, n}(xs, step)
end

function start(it::Partition{I, N}) where {I, N}
    p = Vector{eltype(I)}(undef, N)
    s = start(it.xs)
    for i in 1:(N - 1)
        if done(it.xs, s)
            break
        end
        (p[i], s) = next(it.xs, s)
    end
    (s, p)
end

function next(it::Partition{I, N}, state) where {I, N}
    (s, p0) = state
    (x, s) = next(it.xs, s)
    ans = p0; ans[end] = x

    p = similar(p0)
    overlap = max(0, N - it.step)
    for i in 1:overlap
        p[i] = ans[it.step + i]
    end

    # when step > n, skip over some elements
    for i in 1:max(0, it.step - N)
        if done(it.xs, s)
            break
        end
        (x, s) = next(it.xs, s)
    end

    for i in (overlap + 1):(N - 1)
        if done(it.xs, s)
            break
        end

        (x, s) = next(it.xs, s)
        p[i] = x
    end

    (tuple(ans...), (s, p))
end

done(it::Partition, state) = done(it.xs, state[1])

# Group output from an iterator based on a key function.
# Consecutive entries from the iterator with the same
# key value will be returned in a single array.
# Inspired by itertools.groupby in python.
# E.g.,
#   x = ["face", "foo", "bar", "book", "baz", "zzz"]
#   groupby(z -> z[1], x) =
#       ["face", "foo"]
#       ["bar", "book", "baz"]
#       ["zzz"]
struct GroupBy{I, F<:Base.Callable}
    keyfunc::F
    xs::I
end
IteratorSize(::Type{<:GroupBy}) = SizeUnknown()

# eltype{I}(it::GroupBy{I}) = I
eltype(::Type{GroupBy{I, F}}) where {I, F} = Vector{eltype(I)}

"""
    groupby(f, xs)

Group consecutive values that share the same result of applying `f`.

```jldoctest
julia> for i in groupby(x -> x[1], ["face", "foo", "bar", "book", "baz", "zzz"])
           @show i
       end
i = String["face", "foo"]
i = String["bar", "book", "baz"]
i = String["zzz"]
```
"""
function groupby(keyfunc::Base.Callable, xs)
    GroupBy(keyfunc, xs)
end

function start(it::GroupBy)
    s = start(it.xs)
    prev_value = nothing
    prev_key = nothing
    return (s, (prev_key, prev_value))
end

function next(it::GroupBy{I}, state) where I
    (s, (prev_key, prev_value)) = state
    values = Vector{eltype(I)}()
    # We had a left over value from the last time the key changed.
    if prev_value != nothing || prev_key != nothing
        push!(values, prev_value)
    end
    prev_value = nothing
    while !done(it.xs, s)
        (x, s) = next(it.xs, s)
        key = it.keyfunc(x)
        # Did the key change?
        if prev_key != nothing && key != prev_key
            prev_key = key
            prev_value = x
            break
        else
            push!(values, x)
        end
        prev_key = key
    end
    # We either reached the end of the input or the key changed,
    # either way emit what we have so far.
    return (values, (s, (prev_key, prev_value)))
end

function done(it::GroupBy, state)
    return state[2][2] == nothing && done(it.xs, state[1])
end

# Like map, except returns the output as an iterator.  The iterator
# is done when any of the input iterators have been exhausted.
# E.g.,
#   imap(+, count(), [1, 2, 3]) = 1, 3, 5 ...
struct IMap{F<:Base.Callable, T<:Tuple}
    mapfunc::F
    xs::T
end

function IteratorSize(::Type{IMap{F, T}}) where {F, T}
    mapreduce_tt(IteratorSize, shortest, HasLength(), T)
end
IteratorEltype(::Type{<:IMap}) = EltypeUnknown()
length(it::IMap) = minimum(length(x) for x in it.xs if has_length(x))

"""
    imap(f, xs1, [xs2, ...])

Iterate over values of a function applied to successive values from one or more iterators.

```jldoctest
julia> for i in imap(+, [1,2,3], [4,5,6])
            @show i
       end
i = 5
i = 7
i = 9
```
"""
function imap(mapfunc, it1, its...)
    IMap(mapfunc, (it1, its...))
end

function start(it::IMap)
    map(start, it.xs)
end

function next(it::IMap, state)
    next_result = map(next, it.xs, state)
    return (
        it.mapfunc(map(first, next_result)...),
        map(last, next_result)
    )
end

function done(it::IMap, state)
    any(map(done, it.xs, state))
end


# Iterate over all subsets of an indexable collection

struct Subsets{C}
    xs::C
end
IteratorSize(::Type{Subsets{C}}) where {C} = longest(HasLength(), IteratorSize(C))

eltype(::Type{Subsets{C}}) where {C} = Vector{eltype(C)}
length(it::Subsets) = 1 << length(it.xs)

"""
    subsets(xs)
    subsets(xs, k)
    subsets(xs, Val{k}())

Iterate over every subset of the indexable collection `xs`. You can restrict the subsets to a
specific size `k`.

Giving the subset size in the form `Val{k}()` allows the compiler to produce code optimized
for the particular size requested. This leads to performance comparable to hand-written
loops if `k` is small and known at compile time, but may or may not improve performance
otherwise.

```jldoctest
julia> for i in subsets([1, 2, 3])
          @show i
       end
i = Int64[]
i = [1]
i = [2]
i = [1, 2]
i = [3]
i = [1, 3]
i = [2, 3]
i = [1, 2, 3]

julia> for i in subsets(1:4, 2)
          @show i
       end
i = [1, 2]
i = [1, 3]
i = [1, 4]
i = [2, 3]
i = [2, 4]
i = [3, 4]

julia> for i in subsets(1:4, Val{2}())
           @show i
       end
i = (1, 2)
i = (1, 3)
i = (1, 4)
i = (2, 3)
i = (2, 4)
i = (3, 4)
```
"""
function subsets(xs)
    Subsets(xs)
end

function start(it::Subsets)
    # one extra bit to indicated that we are at the end
    fill(false, length(it.xs) + 1)
end

function next(it::Subsets, state)
    ss = it.xs[state[1:end-1]]

    state = copy(state)
    state[1] = !state[1]
    for i in 2:length(state)
        if !state[i-1]
            state[i] = !state[i]
        else
            break
        end
    end

    (ss, state)
end

function done(it::Subsets, state)
    state[end]
end


# Iterate over all subsets of an indexable collection with a given size

struct Binomial{Collection}
    xs::Collection
    n::Int64
    k::Int64
end
Binomial(xs::C, n::Integer, k::Integer) where {C} = Binomial{C}(xs, n, k)

IteratorSize(::Type{<:Binomial}) = HasLength()
IteratorEltype(::Type{Binomial{C}}) where {C} = IteratorEltype(C)

eltype(::Type{Binomial{C}}) where {C} = Vector{eltype(C)}
length(it::Binomial) = binomial(it.n,it.k)

subsets(xs, k) = Binomial(xs, length(xs), k)

mutable struct BinomialIterState
    idx::Vector{Int64}
    done::Bool
end

function start(it::Binomial)
    BinomialIterState(collect(Int64, 1:it.k), (it.k > it.n) ? true : false)
end

function next(it::Binomial, state::BinomialIterState)
    idx = state.idx
    set = it.xs[idx]
    i = it.k
    while i > 0
        if idx[i] < it.n - it.k + i
            idx[i] += 1

            for j in 1:it.k-i
                idx[i+j] = idx[i] + j
            end

            break
        else
            i -= 1
        end
    end

    state.done = i == 0

    return set, state
end

done(it::Binomial, state::BinomialIterState) = state.done


# Iterate over all subsets of an indexable collection with a given *statically* known size

struct StaticSizeBinomial{K, Container}
    xs::Container
end

IteratorSize(::Type{StaticSizeBinomial{K, C}}) where {K, C} = HasLength()
IteratorEltype(::Type{StaticSizeBinomial{K, C}}) where {K, C} = IteratorEltype(C)

eltype(::Type{StaticSizeBinomial{K, C}}) where {K, C} = NTuple{K, eltype(C)}
length(it::StaticSizeBinomial{K}) where {K} = binomial(length(it.xs), K)

subsets(xs::C, ::Val{K}) where {K, C} = StaticSizeBinomial{K, C}(xs)

# Special cases for K == 0
start(it::StaticSizeBinomial{0}) = false
next(it::StaticSizeBinomial{0}, _) = (), true
done(it::StaticSizeBinomial{0}, d) = d

# Generic case K >= 1
pop(t::NTuple) = reverse(Base.tail(reverse(t))), t[end]

function advance(it::StaticSizeBinomial{K}, idx) where {K}
	xs = it.xs
	lidx, i = pop(idx)
    i += 1
	if i > length(xs) - K + length(idx)
		lidx = advance(it, lidx)
		i = lidx[end] + 1
	end
	return (lidx..., i)
end
advance(it::StaticSizeBinomial, idx::NTuple{1}) = (idx[end]+1,)

start(it::StaticSizeBinomial{K}) where {K} = ntuple(identity, Val{K}())
next(it::StaticSizeBinomial, idx) = map(i -> it.xs[i], idx), advance(it, idx)
done(it::StaticSizeBinomial, state) = state[end] > length(it.xs)


# nth : return the nth element in a collection

"""
    nth(xs, n)

Return the `n`th element of `xs`. This is mostly useful for non-indexable collections.

```jldoctest
julia> mersenne = Set([3, 7, 31, 127])
Set([7, 31, 3, 127])

julia> nth(mersenne, 3)
3
```
"""
function nth(xs, n::Integer)
    n > 0 || throw(BoundsError(xs, n))

    # catch, if possible
    has_length(xs) && (n ≤ length(xs) || throw(BoundsError(xs, n)))

    for (i, val) in enumerate(xs)
        i >= n && return val
    end

    # catch iterators with no length but actual finite size less then n
    throw(BoundsError(xs, n))
end

nth(xs::Union{Tuple, Array}, n::Integer) = xs[n]

function nth(xs::AbstractArray, n::Integer)
    idx = eachindex(xs)[n]
    return @inbounds xs[idx]
end


# takenth(xs,n): take every n'th element from xs

struct TakeNth{I}
    xs::I
    interval::UInt
end
IteratorSize(::Type{TakeNth{I}}) where {I} = longest(HasLength(), IteratorSize(I))
IteratorEltype(::Type{TakeNth{I}}) where {I} = IteratorEltype(I)
eltype(::Type{TakeNth{I}}) where {I} = eltype(I)
length(x::TakeNth) = div(length(x.xs), x.interval)

"""
    takenth(xs, n)

Iterate through every `n`th element of `xs`.

```jldoctest
julia> collect(takenth(5:15,3))
3-element Array{Int64,1}:
  7
 10
 13
```
"""
function takenth(xs, interval::Integer)
    if interval <= 0
        throw(ArgumentError(string("expected interval to be 1 or more, ",
                                   "got $interval")))
    end
    TakeNth(xs, convert(UInt, interval))
end


function iterate(it::TakeNth, state=())
    xs_iter = nothing

    for i = 1:it.interval
        xs_iter = iterate(it.xs, state...)
        xs_iter === nothing && return nothing
        state = tail(xs_iter)
    end

    val, xs_state = xs_iter
    return (val, (xs_state,))
end


struct Iterated{T}
    f::Function
    seed::T
end
IteratorSize(::Type{<:Iterated}) = IsInfinite()
IteratorEltype(::Type{<:Iterated}) = EltypeUnknown()

"""
    iterated(f, x)

Iterate over successive applications of `f`, as in `x`, `f(x)`, `f(f(x))`, `f(f(f(x)))`, ...

Use `Base.Iterators.take()` to obtain the required number of elements.

```jldoctest
julia> for i in Iterators.take(iterated(x -> 2x, 1), 5)
           @show i
       end
i = 1
i = 2
i = 4
i = 8
i = 16

julia> for i in Iterators.take(iterated(sqrt, 100), 6)
           @show i
       end
i = 100
i = 10.0
i = 3.1622776601683795
i = 1.7782794100389228
i = 1.333521432163324
i = 1.1547819846894583
```
"""
iterated(f, seed) = Iterated(f, seed)

iterate(it::Iterated) = (it.seed, it.seed)
function iterate(it::Iterated, state)
    newval = it.f(state)
    return (newval, newval)
end

# peekiter(iter): possibility to peek the head of an iterator

struct PeekIter{I}
    it::I
end

"""
    peekiter(xs)

Lets you peek at the head element of an iterator without updating the state.

```jldoctest
julia> it = peekiter(["face", "foo", "bar", "book", "baz", "zzz"])
IterTools.PeekIter{Array{String,1}}(String["face", "foo", "bar", "book", "baz", "zzz"])

julia> s = start(it)
(2, Nullable{String}("face"))

julia> @show peek(it, s);
peek(it, s) = Nullable{String}("face")

julia> @show peek(it, s);
peek(it, s) = Nullable{String}("face")

julia> x, s = next(it, s)
("face", (3, Nullable{String}("foo"), false))

julia> @show x;
x = "face"

julia> @show peek(it, s);
peek(it, s) = Nullable{String}("foo")
```
"""
peekiter(itr) = PeekIter(itr)

eltype(::Type{PeekIter{I}}) where {I} = eltype(I)
IteratorSize(::Type{PeekIter{I}}) where {I} = IteratorSize(I)
IteratorEltype(::Type{PeekIter{I}}) where {I} = IteratorEltype(I)
length(f::PeekIter) = length(f.it)
size(f::PeekIter) = size(f.it)

function iterate(pit::PeekIter, state=iterate(pit.it))  # maybe state=iterate(pit.it)?
    state === nothing && return nothing
    val, it_state = state
    return (val, iterate(pit.it, it_state))
end

peek(pit::PeekIter, state) = state === nothing ? nothing : Some{eltype(pit)}(first(state))

#NCycle - cycle through an object N times

struct NCycle{I}
    iter::I
    n::Int
end

"""
    ncycle(iter, n)

Cycle through `iter` `n` times.

```jldoctest
julia> for i in ncycle(1:3, 2)
           @show i
       end
i = 1
i = 2
i = 3
i = 1
i = 2
i = 3
```
"""
ncycle(iter, n::Int) = NCycle(iter, n)

eltype(nc::NCycle{I}) where {I} = eltype(I)
length(nc::NCycle) = nc.n*length(nc.iter)
IteratorSize(::Type{NCycle{I}}) where {I} = longest(HasLength(), IteratorSize(I))
IteratorEltype(::Type{NCycle{I}}) where {I} = IteratorEltype(I)

function iterate(nc::NCycle, state=(nc.n,))
    nc.n <= 0 && return nothing  # don't do anything if we aren't iterating

    n, inner_state = first(state), tail(state)
    inner_iter = iterate(nc.iter, inner_state...)

    if inner_iter === nothing
        if n <= 1
            return nothing
        else
            inner_iter = iterate(nc.iter)
            inner_iter === nothing && return nothing

            n -= 1
        end
    end

    v, inner_state = inner_iter
    return v, (n, inner_state)
end

end # module IterTools