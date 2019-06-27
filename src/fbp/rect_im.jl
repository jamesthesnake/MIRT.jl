using Plots

"""
`phantom = rect_im(ig, params;
oversample=1, hu_scale=1, fov=ig.fov, chat=false, how=:auto, replace=false, return_params=false)`

generate rectangle phantom image from parameters:
    `[x_center y_center x_width y_width angle_degrees amplitude]`

in
    `ig`						image_geom() object
    `params`		[Nrect,6]	rect parameters. if empty use default

options
    `oversample`	int     oversampling factor, for grayscale boundaries
    `hu_scale`		float   use 1000 to scale
    `fov`           float   default ig.fov
	`chat`		   	bool
	`how`			symbol	:fast or :slow
	`replace`		bool
	`return_params` bool	if true, return both phantom and params

out
    `phantom`			[nx ny] image
	`params`			[Nrect,6] rect parameters (only return if return_params=true)

"""
function rect_im(ig::MIRT_image_geom,
    params::AbstractArray{<:Real,2};
    oversample::Integer=1,
    hu_scale::Real=1,
    fov::Real=ig.fov,
	chat::Bool=false,
	how::Symbol=:auto,
	replace::Bool=false,
	return_params::Bool=false)

	if oversample > 1
    	ig = ig.over(oversample)
    end
    args = (ig.nx, ig.ny, ig.dx, ig.dy, ig.offset_x, ig.offset_y, replace)

	if isempty(fov)
		fov = ig.fov
	end
	#=
	if isempty(params)
		params = rect_im_default_parameters(xfov, yfov)
	end
	=#

    params[:,6] .*= hu_scale

    do_fast = params[:,5] .== 0 # default for :auto
    if how == :fast
            do_fast[:] .= true
    elseif how == :slow
            do_fast[:] .= false
    elseif how != :auto
         throw("bad how :how")
    end

    phantom = zeros(Float32, ig.nx, ig.ny)

    if any(do_fast)
        phantom += rect_im_fast(params[do_fast,:], args...)
	end

	if any(.!do_fast)
		phantom += rect_im_slow(params[.!do_fast,:], args..., oversample)
	end

	if oversample > 1
		phantom = downsample2(phantom, oversample)
	end

	if return_params
		return (phantom, params)
	end
	return phantom
end

"""
`phantom = rect_im_fast()`
"""
function rect_im_fast(params_in, nx, ny, dx, dy, offset_x, offset_y, replace)
    params = copy(params_in)
    if size(params,2) != 6
		throw("bad ellipse parameter vector size")
	end

	phantom = zeros(Float32, nx, ny)

	wx = (nx-1)/2 + offset_x # scalars
	wy = (ny-1)/2 + offset_y
	x1 = ((0:nx-1) .- wx) * dx # arrays
	y1 = ((0:ny-1) .- wy) * dy
	fun = (x1, x2, wx) -> # integrated rect(x/wx) function from x1 to x2
		max(min(x2, wx/2) - max(x1, -wx/2), 0)

	# ticker reset
	ne = size(params)[1]
	for ie in 1:ne
		#ticker(mfilename, ie, ne)
		rect = params[ie, :]
		cx = rect[1]
		wx = rect[3]
		cy = rect[2]
		wy = rect[4]
		theta = rect[5] * (pi/180)
		if theta != 0
			throw("theta=0 required")
		end
		x = x1 .- cx
		y = y1 .- cy
		tx = fun.(x.-abs(dx)/2, x.+abs(dx)/2, wx) / abs(dx)
		ty = fun.(y.-abs(dy)/2, y.+abs(dy)/2, wy) / abs(dy)
		tmp = Float32.(tx) * Float32.(ty)' # outer product (separable)
		if replace
			phantom[tmp .> 0] .= rect[6]
		else
			phantom = phantom + rect[6] * tmp
		end
	end
	return phantom
end

"""
`phantom = rect_im_slow()`
"""
function rect_im_slow(params_in, nx, ny, dx, dy, offset_x, offset_y, replace, over)
	params = copy(params_in)
	if size(params,2) != 6
		throw("bad rect parameter vector size")
	end
	phantom = zeros(Float32, nx*over, ny*over)

	wx = (nx*over - 1)/2 + offset_x*over # scalar
	wy = (ny*over - 1)/2 + offset_y*over
	xx = ((0:nx*over-1) .- wx) * dx / over # Array{Float64,2}
	yy = ((0:ny*over-1) .- wy) * dy / over
	(xx, yy) = ndgrid(xx, yy)
	# ticker reset
	ne = size(params)[1]
	for ie in 1:ne
		#ticker(mfilename, ie, ne)

		rect = params[ie, :]
		cx = rect[1] # float64
		wx = rect[3]
		cy = rect[2]
		wy = rect[4]
		theta = rect[5] * (pi/180) #float64

		x = cos(theta) .* (xx.-cx) + sin(theta) .* (yy.-cy) #Array{Float64,2}
		y = -sin(theta) .* (xx.-cx) + cos(theta) .* (yy.-cy) #Array{Float64,2}
		#typeof(x / wx) is Array{Float64,2}
		#typeof(abs.(x / wx) .< 1/2) is a bit array
		tmp = (abs.(x / wx) .< 1/2) .& (abs.(y / wy) .< 1/2) # typeof(tmp) ?

		if replace
			phantom[tmp .> 0] .= rect[6]
		else
			phantom = phantom + rect[6] * tmp
		end
	end
	return phantom
end

"""
`phantom = rect_im(nx, dx, params; args...)`

square image of size `nx` by `nx`,
specifying pixel size `dx` and rect `params`
"""
function rect_im(nx::Integer, dx::Real, params; args...)
	ig = image_geom(nx=nx, dx=1)
	return rect_im(ig, params; args...)
end

"""
`phantom = rect_im(nx::Integer, params; args...)`

square image of size `nx` by `nx` with
pixel size `dx=1` and ellipse `params`
"""
function rect_im(nx::Integer, params; args...)
	return ellipse_im(nx, 1., params; args...)
end

"""
`phantom = rect_im(nx::Integer; ny::Integer=nx, dx::Real=1)`

image of size `nx` by `ny` (default `nx`) with specified `dx` (default 1),
defaults to `:my_rect`
"""
function rect_im(nx::Integer; ny::Integer=nx, dx::Real=1, args...)
	if image_geom(nx=nx, ny=ny, dx=dx, args...)
		return rect_im(ig, :my_rect; args...)
	end
end

"""
`phantom = rect_im(nx::Integer, ny::Integer; args...)`

`:my_rect` of size `nx` by `ny`
"""
function rect_im(nx::Integer, ny::Integer; args...)
	return rect_im(nx, ny=ny, dx=1.; args...)
end

"""
`phantom = rect_im(ig, code, args...)`

`code = :my_rect | :default`
"""
function rect_im(ig::MIRT_image_geom, params::Symbol; oversample, chat, args...)
	fov = ig.fov
	if params == :my_rect
		params = my_rect(fov, fov)
	elseif params == :default
		params = rect_im_default_parameters(fov, fov)
	elseif params == :smiley
		params = smiley_parameters(fov, fov)
	else
		throw("bad phantom symbol $params")
	end
	return rect_im(ig, params; args...)
end

"""
`phantom = rect_im(ig; args...)`

`:default` (default) for given image geometry `ig`
"""
function rect_im(ig::MIRT_image_geom; args...)
	return rect_im(ig, :default; args...)
end



"""
`(xx,yy) = ndgrid(x,y)`
"""
function ndgrid(x::AbstractVector{<:Number},
				y::AbstractVector{<:Number})
	return (repeat(x, 1, length(y)), repeat(y', length(x), 1))
end

"""
`(xr,yr) = rot2(x, y, theta)`
2D rotation
"""
function rot2(x, y, theta)
	xr = cos(theta) * x + sin(theta) * y
	yr = -sin(theta) * x + cos(theta) * y
	return (xr, yr)
end

"""
`params = rect_im_default_parameters(xfov, yfov)`

default parameters
"""
function rect_im_default_parameters(xfov, yfov)
	f = 1/64
	params = [
		0     0     50     50     0     1
		10    -16	25	   16	  0	    -0.5
		-13	  15	13	   13	  1*45  1
		-18   0     1      1      0     1
		-12   0     1      1      0     1
		-6    0     1      1      0     1
		0     0     1      1      0     1
		6     0     1      1      0     1
		12    0     1      1      0     1
		18    0     1      1      0     1
	]

	params[:,[1,3]] .*= xfov/64 # x_center and x_width
	params[:,[2,4]] .*= yfov/64 # y_center and y_width

	return params
end


"""
`params = my_rect(xfov, yfov)`
"""
function my_rect(xfov, yfov)
	f=1/64
	rect = [
	35	35	20	10	45	1
	35	-35	20	10	-45	1
	-35	-35	20	10	45	1
	-35	35	20	10	-45	1
	0	0	40	40	45	1
	0	0	40	40	0	0.5
	40	0	12	1.5	0	1.5
	-40	0	12	1.5	0	1.5
	]
	return rect
end

"""
`params = smiley_parameters(xfov, yfov)`

smiley face out of rects
"""
function smiley_parameters(xfov, yfov)
	rect = [
	0	0	80	80	0	0.5
	-20	-20	10	15	0	1 #eyes
	20	-20	10	15	0	1
	0	25	50	6	0	1 #mouth
	-23	19	4	6	0	1
	23	19	4	6	0	1
	]
	return rect
end

"""
`rect_im()`

show docstring(s)
"""
function rect_im()
	@doc rect_im
end

"""
`rect_im_show()`
"""
function rect_im_show()
	#plot(1:10, 1:10)
	ig = image_geom(nx=2^8, ny=2^8, fov=100)

	x0 = rect_im(ig, [[[0.5, 0, 3, 20]*ig.dx..., 0, 1]';], oversample=3)
	p1 = jim(x0)

	x1 = rect_im(ig, :default; oversample=3, chat=true)
	p2 = jim(x1, title="default rects")

	x2 = rect_im(ig, :my_rect; oversample=3, chat=true)
	p3 = jim(x2, title="my rect")

	x3 =rect_im(ig, :smiley; oversample=3, chat=true)
	p4 = jim(x3, title="smiley")

	plot(p1, p2, p3, p4)
end

function rect_im_test()
	fov = 100
	rect_im_default_parameters(fov, fov)
	ellipse_im_show()
	true
end


"""
`rect_im(:test)`

`rect_im(:show)`

run tests
"""
function rect_im(test::Symbol)
	if test == :show
		return rect_im_show()
	end
	test != :test && throw(ArgumentError("test $test"))
	rect_im()
	rect_im(:show)
	rect_im_test()
end