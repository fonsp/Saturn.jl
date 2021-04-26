### A Pluto.jl notebook ###
# v0.14.0

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ 01b5d868-d33e-4d06-9c18-e0fcf694592c
using Flux

# ╔═╡ 3877e10f-829a-4441-872b-31228498d2fe
# import Pkg; Pkg.add("Flux"); Pkg.add("CUDA"); Pkg.add("CSV"); Pkg.add("DataFrames")

# ╔═╡ f3dca8d3-3098-41fe-b6a3-83ca7035e4a3
# import CUDA

# ╔═╡ 28cccbfd-c12f-463e-ab87-7cc72d14aa36
import Markdown

# ╔═╡ be3b22ce-c323-493c-a9a9-054d064976b1
import CSV

# ╔═╡ 104a851b-4b0e-4a4c-9221-ef7809a0a7e5
import DataFrames

# ╔═╡ a632a154-16a0-4faa-8a77-92644667db4b
import Serialization

# ╔═╡ bd4483a5-dc9e-43c4-9cb8-b29c56a8fc56
gpu = cpu

# ╔═╡ 40978ca3-548b-4668-8cb4-85408d710a10
preprocessed = DataFrames.DataFrame(CSV.File(joinpath(split(@__FILE__, '#')[1] * ".assets", "DriveLab_final_data_preprocessed (1).csv")));

# ╔═╡ 3e9b4198-10ad-410a-a0c1-89835bc94733
data_by_obs = DataFrames.groupby(preprocessed, :Observation);

# ╔═╡ e72821dd-2bcc-490f-a28f-7cd9fe7ee6ba
import Statistics

# ╔═╡ 82ed18cb-a0af-4d64-8dc3-6adde8e673cd
md"## Data wrangling"

# ╔═╡ bde4d5de-bccf-4842-b458-722991f5b32c
WINDOW_SIZE = 256

# ╔═╡ 9f8b1cdd-46b0-458b-88e4-11c1ce14485b
STEP_SIZE = WINDOW_SIZE ÷ 2

# ╔═╡ d7f4147b-dc3a-4fcf-9a06-aecaeca022e3
INPUT_CHANNELS = 3

# ╔═╡ 4e922d5d-22ef-4df0-a2b5-7160cdbfe447
obs_data = let
	obs_data = []

	for data in data_by_obs
		window_entries = []
		window_workload = []
		
		for entry in eachrow(data)
				push!(window_entries, [
					entry[:GSR],
					entry[:RightPupilDiameter],
					entry[:LeftPupilDiameter]
				])
				push!(window_workload, entry[:workload])
		end

		push!(obs_data, (
			entries=collect(Iterators.flatten(window_entries)),
			workloads=window_workload,
		))
	end
	
	obs_data
end;

# ╔═╡ 816a7490-5217-4cfa-8097-a19ed00d0de8
function train_steps(trajectory)
	steps = (length(trajectory[:entries]) - (WINDOW_SIZE * INPUT_CHANNELS)) ÷ (STEP_SIZE * INPUT_CHANNELS) - 3 # 🤷‍♀️
	[begin
		window_start = (step-1)*STEP_SIZE+1
		window_width = WINDOW_SIZE*INPUT_CHANNELS-1
		(
			gpu(trajectory[:entries][window_start:window_start+window_width]), 
			trajectory[:workloads][window_start+window_width]
		)
	end for step in 1:steps]
end

# ╔═╡ e8c2783d-8c8d-492e-a797-e3a9910ede31
observation_steps = [train_steps(trajectory) for trajectory in obs_data];

# ╔═╡ f5113a4b-cc10-4382-8890-82cb9f877a16
md"---"

# ╔═╡ b8d234f1-e2f0-42a9-8859-ecaa0092b70d
@bind observation_number HTML("<input type=range min=1 max=$(length(observation_steps[1])) />")

# ╔═╡ 9f7407b6-a1e1-4548-b7e8-f5baf732e990
observation_steps[1][1]

# ╔═╡ f0658dcb-1a17-4465-91da-e1bf53bc3da7
# optimiser = Descent(0.00000001)

# ╔═╡ 1bb22786-c530-4417-b71c-a6fbbbc5428e
observation_steps[1][5][1]

# ╔═╡ 31f940df-4599-410a-a75c-e57a8f3524ea
optimiser = Flux.ADAM(1e-2)

# ╔═╡ 80178cbc-93a4-4937-b374-ca34c05ab45d
begin
	Base.@kwdef struct BRNN{L,D}
	  forward  :: L
	  backward :: L
	  dense    :: D
	end
	
	Flux.@functor BRNN

	function BRNN(in::Integer, hidden::Integer, out::Integer, σ = relu)
	  return BRNN(
		forward=LSTM(in, hidden), # forward
		backward=LSTM(in, hidden), # backward
		dense=Dense(2*hidden, out, σ)
	  )
	end
	function (m::BRNN)(xs)
	  m.dense(vcat(m.forward(xs), reverse(m.backward(reverse(xs)))))
	end
end

# ╔═╡ 41f8cfa9-2031-4a0c-94fa-a27385be42f5
model = gpu(BRNN(WINDOW_SIZE*INPUT_CHANNELS, 200, 1))

# ╔═╡ 81bbdedd-1110-47eb-a166-2f7a9d81c08d
begin
	Markdown.parse("""
	observation_number: $(observation_number)  
		
	expected: $(observation_steps[1][observation_number][2])  
		
	result: $(model(observation_steps[1][observation_number][1])[1])  
	""")
end

# ╔═╡ 68051f26-bf57-485f-a133-f27e24f63776
function my_loss(entries, workload)
	# y = Flux.onehot(workload, [0,1,2,3,4])
	y = workload
	ŷ = model(entries)[1]
	return (y-ŷ)^2
	# return sum((y .- ŷ).^2)
	# Flux.onehot(workload, [1,2,3,4])
end

# ╔═╡ cae8047b-f8f1-4cc8-b988-3900c2d611e3
first_this = my_loss(observation_steps[1][5]...)

# ╔═╡ bf91e080-a911-4952-a4b0-d24ffcd8ee9c
gs = Flux.gradient(() -> my_loss(observation_steps[1][8]...), params(model))

# ╔═╡ 58f98fc0-ee18-4eb0-8cd7-19f6fbd5079f
(gs.params)

# ╔═╡ 00fd3e5d-3c60-4246-98a0-f91ec4774758
gs[model.forward].x.state

# ╔═╡ d22a7971-303a-419a-9b85-c7720bd7d16c
first_this; for trajectory in observation_steps[1:1]
	Flux.train!(my_loss, Flux.params(model), trajectory, optimiser,
		cb=Flux.throttle(10) do
			@info "my_loss" sum([
					my_loss(window...)
					for window
					in trajectory
			])
		end
	)
end

# ╔═╡ Cell order:
# ╠═3877e10f-829a-4441-872b-31228498d2fe
# ╠═01b5d868-d33e-4d06-9c18-e0fcf694592c
# ╠═f3dca8d3-3098-41fe-b6a3-83ca7035e4a3
# ╠═28cccbfd-c12f-463e-ab87-7cc72d14aa36
# ╠═be3b22ce-c323-493c-a9a9-054d064976b1
# ╠═104a851b-4b0e-4a4c-9221-ef7809a0a7e5
# ╠═a632a154-16a0-4faa-8a77-92644667db4b
# ╠═bd4483a5-dc9e-43c4-9cb8-b29c56a8fc56
# ╠═40978ca3-548b-4668-8cb4-85408d710a10
# ╠═3e9b4198-10ad-410a-a0c1-89835bc94733
# ╠═e72821dd-2bcc-490f-a28f-7cd9fe7ee6ba
# ╟─82ed18cb-a0af-4d64-8dc3-6adde8e673cd
# ╟─bde4d5de-bccf-4842-b458-722991f5b32c
# ╟─9f8b1cdd-46b0-458b-88e4-11c1ce14485b
# ╟─d7f4147b-dc3a-4fcf-9a06-aecaeca022e3
# ╟─4e922d5d-22ef-4df0-a2b5-7160cdbfe447
# ╟─816a7490-5217-4cfa-8097-a19ed00d0de8
# ╠═e8c2783d-8c8d-492e-a797-e3a9910ede31
# ╟─f5113a4b-cc10-4382-8890-82cb9f877a16
# ╟─b8d234f1-e2f0-42a9-8859-ecaa0092b70d
# ╟─81bbdedd-1110-47eb-a166-2f7a9d81c08d
# ╠═9f7407b6-a1e1-4548-b7e8-f5baf732e990
# ╠═68051f26-bf57-485f-a133-f27e24f63776
# ╠═41f8cfa9-2031-4a0c-94fa-a27385be42f5
# ╠═cae8047b-f8f1-4cc8-b988-3900c2d611e3
# ╠═f0658dcb-1a17-4465-91da-e1bf53bc3da7
# ╠═bf91e080-a911-4952-a4b0-d24ffcd8ee9c
# ╠═00fd3e5d-3c60-4246-98a0-f91ec4774758
# ╠═58f98fc0-ee18-4eb0-8cd7-19f6fbd5079f
# ╠═1bb22786-c530-4417-b71c-a6fbbbc5428e
# ╠═31f940df-4599-410a-a75c-e57a8f3524ea
# ╠═d22a7971-303a-419a-9b85-c7720bd7d16c
# ╠═80178cbc-93a4-4937-b374-ca34c05ab45d
