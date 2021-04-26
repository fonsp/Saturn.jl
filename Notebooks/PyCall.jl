### A Pluto.jl notebook ###
# v0.14.0

using Markdown
using InteractiveUtils

# ╔═╡ eb791876-812f-11eb-0a62-f1011dd01e1e
begin
	import Pkg
	Pkg.add("PyCall")
end

# ╔═╡ 479fe42d-c183-4c2d-800d-42ab11a41b36
import PyCall

# ╔═╡ aba3f7a1-acd1-4c9c-9dea-782ba1477d49
numpy = PyCall.pyimport_conda("numpy", "numpy")

# ╔═╡ 749d4ed1-1005-42e9-862c-601692d2841f
pandas = PyCall.pyimport_conda("pandas", "pandas")

# ╔═╡ 2d27684f-7cba-462d-bac9-8710fed05825
stats = PyCall.pyimport_conda("scipy.stats", "scipy")

# ╔═╡ 824258ab-258e-4570-ae94-e8eebb375c93
tao_optimizers = PyCall.pyimport_conda("estimagic.optimization.tao_optimizers", "estimagic", "opensourceeconomics")

# ╔═╡ 3eb02c1d-0167-4bbd-a661-4b647212af79


# ╔═╡ 210d6115-e6ab-4067-b5fa-ee0ddda369b4


# ╔═╡ 8aecaac6-3475-450c-abe0-793079078f69


# ╔═╡ 6b1b63e5-b4bc-46c1-a7a7-d7d8530173be
function get_conda_import(module_name, package_spec)
	@info "Hey" module_name package_spec
	if length(package_spec.args) == 1
		package_name = package_spec.args[1]
		:(PyCall.pyimport_conda($(module_name), $(string(package_name))))
	elseif length(package_spec.args) == 2
		repo_name, package_name = package_spec.args
		:(PyCall.pyimport_conda($(module_name), $(string(package_name)), $(string(repo_name))))
	else
		throw("Nope")
	end
end

# ╔═╡ 1ee7d3d4-16e0-45ce-ab66-bfbfc0cad0c8
pointvalue

# ╔═╡ 1e2dd1f4-3c9b-4d6e-a52c-11c204220884
function py_import(import_spec)
	if import_spec.head == :(:)
		module_spec, local_names... = import_spec.args
		quote
			$((begin
				module_name = length(name.args) == 1 ? string(name.args[1]) : string(name)
				local_name = name.args[end]
				:($(local_name) = $(get_conda_import(module_name, module_spec)))
			end for name in local_names)...)
		end
	elseif import_spec.head == :(.)
		if length(import_spec.args) == 1
			module_name = string(import_spec.args[1])
			PyCall.pyimport_conda(module_name, module_name)
		elseif length(import_spec.args) == 2
			package_name, module_name = import_spec.args
			PyCall.pyimport_conda(string(package_name), string(module_name))
		end
	elseif import_spec.head == :(as)
		10
	end
end

# ╔═╡ e28ef9bd-eab0-4836-815b-c0d7465f4b99
py_import; macro py(expr)
	if expr.head == :import
		quote $(py_import)($(expr.args)...) end
	else
		throw("Nope")
	end
end

# ╔═╡ 70a3af6e-7872-4b3a-aeb3-f657b04f91a5
z3 = @py import scipy: stats2, optimize2, special2

# ╔═╡ 5af71d47-e8fc-4198-bb68-b29f8f39ae0f
x = optimizations.tao_optimizers

# ╔═╡ ec80a7a5-9268-4591-bc43-be806a433c7a
x.tao_pounders

# ╔═╡ 95991bdf-500d-4199-bd83-e32d57a3903c
@eval macro $(:try)(expr)
	quote
		try
			$(expr)	
		catch e
			e
		end
	end
end

# ╔═╡ 4b342c7d-e82d-43c1-8888-eed9fd59236f
macro pyimport(name)
	quote
		@pyimport $(name) from $(name)
	end
end

# ╔═╡ 8f512850-89ff-4ec2-985d-22b83db13360
macro pyimport(name, _from, specifier)
	module_and_channel = split(string(specifier), "#")
	if length(module_and_channel) == 1
		module_name, = module_and_channel
		quote
			PyCall.pyimport_conda($(string(name)), $(module_name))
		end
	else
		module_name, channel = module_and_channel
		quote
			PyCall.pyimport_conda($(string(name)), $(module_name), $(channel))
		end

	end
end

# ╔═╡ b3250d58-726a-44e9-8c1f-4a89053cf27e
macro pyimport(name, _from, module_name, channel)
	PyCall.pyimport_conda($(string(name)), $(module_name), $(channel))
end

# ╔═╡ 5fa34023-0c92-457c-ba58-acaab4dd6bd8
optimize = @pyimport scipy.stats from scipy

# ╔═╡ 3abf129b-ce82-4fa4-bacc-d3bb69c6a45a
special = @pyimport scipy.special from scipy

# ╔═╡ 12cfab00-a4eb-4fd2-9c3a-45ecd665ee55
multiprocessing = @pyimport multiprocessing

# ╔═╡ df0025c5-9c70-4a11-8dcf-d080d3e7fe4b
datetime = @pyimport datetime

# ╔═╡ f32d33c7-3fa6-4331-804d-710abb7ce896
tao_optimizers2 = @pyimport estimagic.optimization.tao_optimizers from estimagic (opensourceeconomics)

# ╔═╡ 3510ed8f-dbdf-4558-be0c-adb480562d32
macro identity(expr)
	QuoteNode(expr)
end

# ╔═╡ b4d1ac2d-f110-40f7-828f-3548b43b9bd4
expr = @identity import opensourceeconomics.estimagic: estimagic.optimization.tao_optimizers as module_name

# ╔═╡ ef017c39-4c0b-464b-94aa-98238b856927
expr.args[1].args[1]

# ╔═╡ 8cedaaf3-e862-46d5-b37c-2a3cb5699518
z = @identity import numpy as np

# ╔═╡ d7e8b1d6-cdd1-466a-a885-0c40835981a9
z.args[1].args[1]

# ╔═╡ 8b010349-4fd7-487a-a39d-755493dadef9
@identity (hey)

# ╔═╡ de0757f0-f20e-464d-9c8c-fa29d28ca44b
error = @try PyCall.py"""
import os
import numpy as np
import pandas as pd
from scipy import stats, optimize, special
import multiprocessing as mp
import datetime
import copy
#from estimagic.optimization.tao_optimizers import tao_pounders as pounders

glquadtable = np.array([[0.07053988969198875,	0.16874680185111386],
                        [0.37212681800161144,	0.29125436200606828],
                        [0.91658210248327356,	0.26668610286700129],
                        [1.70730653102834388,	0.16600245326950684],
                        [2.74919925530943213,	0.074826064668792371],
                        [4.0489253138508869,	0.0249644173092832211],
                        [5.6151749708616165,	0.006202550844572237],
                        [7.4590174536710633,	0.0011449623864769082],
                        [9.5943928695810968,	1.55741773027811975e-4],
                        [12.0388025469643163,	1.54014408652249157e-5],
                        [14.81429344263074,	1.08648636651798235e-6],
                        [17.948895520519376,	5.3301209095567148e-8],
                        [21.478788240285011,	1.757981179050582e-9],
                        [25.4517027931869055,	3.7255024025123209e-11],
                        [29.932554631700612,	4.7675292515781905e-13],
                        [35.013434240479,	3.372844243362438e-15],
                        [40.8330570567285711,	1.15501433950039883e-17],
                        [47.6199940473465021,	1.53952214058234355e-20],
                        [55.8107957500638989,	5.286442725569158e-24],
                        [66.5244165256157538,	1.6564566124990233e-28]]) #https://keisan.casio.com/exec/system/1281279441#

# ghquadtable = np.asarray(pd.read_csv("ghquadtable.csv"))

primes = np.ravel(np.asarray(pd.read_csv("primes.txt",delim_whitespace=True,skiprows=[0,1,2,1004],header=None))) #https://primes.utm.edu/lists/small/10000.txt

#############################################
#SECTION 2: quasiMC and quadrature functions
#############################################0
def qmctorus(lnth,prim):
    primmat = np.transpose(np.tile(prim,(lnth,1)))
    kmat = np.tile(range(1,lnth+1),(len(prim),1))
    qmcmat, _ = np.modf(kmat*np.sqrt(primmat))
    return qmcmat     

def cdfstatevar(x,ptarget,ppois,nu,zmax): #used to generate quantiles from state variable distribution
    return np.average(stats.gamma.cdf(np.repeat(x,zmax+1),np.repeat(nu,zmax+1)+np.array(range(zmax+1))),weights=stats.poisson.pmf(range(zmax+1),ppois)) - ptarget 

"""

# ╔═╡ 276a9a45-ef96-455e-a9e4-9a0258f1566c
value = string(error.val)

# ╔═╡ d573b4f9-0f81-4615-95a0-f83485cf3ef7
public_properties = filter(propertynames(error.val)) do x
	if contains(string(x), "__") 
		return false
	end
	value = getproperty(error.val, x)
	if PyCall.py"""callable($(value))"""
		return false
	end
	return true
end

# ╔═╡ dc8a3bbc-5b00-4150-b128-ab5645fc45de
Dict(x => getproperty(error.val, x) for x in public_properties)

# ╔═╡ 79ecba06-1a0a-48e1-8757-7329e6e56231
primes_path = joinpath(split(@__FILE__, '#')[1] * ".assets", "primes.txt")

# ╔═╡ 561fe73b-7838-461d-a1eb-308a056e03e4
PyCall.py"""
import os
import numpy as np
import pandas as pd
from scipy import stats, optimize, special
import multiprocessing as mp
import datetime
import copy
from estimagic.optimization.tao_optimizers import tao_pounders as pounders

#############################################
#SECTION 1: Hardcoded numerical basis
#############################################

glquadtable = np.array([[0.07053988969198875,	0.16874680185111386],
                        [0.37212681800161144,	0.29125436200606828],
                        [0.91658210248327356,	0.26668610286700129],
                        [1.70730653102834388,	0.16600245326950684],
                        [2.74919925530943213,	0.074826064668792371],
                        [4.0489253138508869,	0.0249644173092832211],
                        [5.6151749708616165,	0.006202550844572237],
                        [7.4590174536710633,	0.0011449623864769082],
                        [9.5943928695810968,	1.55741773027811975e-4],
                        [12.0388025469643163,	1.54014408652249157e-5],
                        [14.81429344263074,	1.08648636651798235e-6],
                        [17.948895520519376,	5.3301209095567148e-8],
                        [21.478788240285011,	1.757981179050582e-9],
                        [25.4517027931869055,	3.7255024025123209e-11],
                        [29.932554631700612,	4.7675292515781905e-13],
                        [35.013434240479,	3.372844243362438e-15],
                        [40.8330570567285711,	1.15501433950039883e-17],
                        [47.6199940473465021,	1.53952214058234355e-20],
                        [55.8107957500638989,	5.286442725569158e-24],
                        [66.5244165256157538,	1.6564566124990233e-28]]) #https://keisan.casio.com/exec/system/1281279441#

ghquadtable = np.asarray(pd.read_csv($(ghquadtable_path)))

primes = np.ravel(np.asarray(pd.read_csv($(primes_path),delim_whitespace=True,skiprows=[0,1,2,1004],header=None))) #https://primes.utm.edu/lists/small/10000.txt


#############################################
#SECTION 2: quasiMC and quadrature functions
#############################################0
def qmctorus(lnth,prim):
    primmat = np.transpose(np.tile(prim,(lnth,1)))
    kmat = np.tile(range(1,lnth+1),(len(prim),1))
    qmcmat, _ = np.modf(kmat*np.sqrt(primmat))
    return qmcmat     

def cdfstatevar(x,ptarget,ppois,nu,zmax): #used to generate quantiles from state variable distribution
    return np.average(stats.gamma.cdf(np.repeat(x,zmax+1),np.repeat(nu,zmax+1)+np.array(range(zmax+1))),weights=stats.poisson.pmf(range(zmax+1),ppois)) - ptarget 
    
def qmcstategrid(pars,hyperpars): #returns a state variable grid
    nu = pars[8]
    xi = pars[9]
    rho_x = pars[10]
    Tt = hyperpars["Tt"]
    K = hyperpars["qmcXsize"]
  
    qmcmat = qmctorus(K,primes[(5*Tt):(6*Tt)])
    ygrid = np.zeros((Tt,K))
  
    for i in range(K):
        ygrid[0,i] = optimize.brentq(cdfstatevar,0,1000,args=(qmcmat[0,i],rho_x*nu/(1-rho_x),nu,hyperpars["zmax"]))
  
    for t in range(1,Tt):
        for i in range(K):
            ygrid[t,i] = optimize.brentq(cdfstatevar,0,1000,args=(qmcmat[t,i],rho_x*ygrid[t-1,i],nu,hyperpars["zmax"]))
  
    xgrid = xi*ygrid
    return(xgrid)

def qmcaggcgrid(pars,hyperpars): #returns an aggregate consumption grid
    mu = pars[11]
    sigma_a = pars[12]
    Tt = hyperpars["Tt"]
    
    qmcmat = qmctorus(hyperpars["qmcXsize"],primes[(4*Tt):(5*Tt)])
    aggcgrid = mu + stats.norm.ppf(qmcmat)*sigma_a #TODO: trim support normal
    return(aggcgrid)

def qmcdeltagrid(pars,hyperpars,statevec): #returns a grid of values for delta_{i,t}
    sigma = pars[13]
    omega_hat = pars[14]
    sigma_hat = pars[15]
    Tt = hyperpars["Tt"]

    qmcmat = qmctorus(hyperpars["qmcDsize"],primes[0:(4*Tt)])
    etagrid = stats.norm.ppf(qmcmat[0:(2*Tt),:]) #TODO: trim support normal
    jgrid1 = stats.poisson.ppf(qmcmat[(2*Tt):(3*Tt),:],np.tile(statevec,(hyperpars["qmcDsize"],1)).transpose())
    jgrid2 = stats.poisson.ppf(qmcmat[(3*Tt):(4*Tt),:],omega_hat)
    deltagrid = np.sqrt(jgrid1)*sigma*etagrid[0:Tt,:] - jgrid1*sigma*sigma/2 + np.sqrt(jgrid2)*sigma_hat*etagrid[Tt:(2*Tt),] - jgrid2*sigma_hat*sigma_hat/2
    for t in range(1,Tt):
        deltagrid[t,] = deltagrid[t-1,] + deltagrid[t,]
    
    return(np.exp(deltagrid))

#############################################
#SECTION 3: h, MRS and Euler
#############################################
def hgridfun(pars,aggcons,deltamat): #generates a grid of h for a grid of delta
    a = pars[0]
    phi = pars[2]
  
    Tt = len(aggcons)
    K = np.size(deltamat,1)
    h = np.zeros((Tt,K))
    h[0,:] = np.repeat(np.exp(-aggcons[0]),K)/deltamat[0,:]
    h[1,:] = (np.ones(K)+phi*(deltamat[0,:]-np.ones(K)))/deltamat[1,:]*np.repeat(np.exp(aggcons[1]),K) + np.repeat((1-a),K)/deltamat[0,:]/np.repeat(np.exp(aggcons[0])*np.exp(aggcons[1]),K)
    for t in range(2,Tt):
        h[t,:] = (np.ones(K)+phi*(deltamat[t-1,:]-np.ones(K)))/deltamat[t,:]/np.repeat(np.exp(aggcons[t]),K)
        for j in range(1,t):
            h[t,:] = h[t,:] + ((1-a)**j)*(np.ones(K)+phi*(deltamat[t-j-1,:]-np.ones(K)))/deltamat[t,:]/np.repeat(np.exp(np.sum(aggcons[(t-j):(t+1)])),K)
    return(h)

def mrsxmrs(row,pars,deltavec,hvec,statevar): #returns the future MRS, the lhs of the Euler eq. and the proportion of households that dropped out 
    a = pars[0]
    b = pars[1]
    phi = pars[2]
    gamma = pars[3]
    rho = pars[4]
    alpha_d = pars[5]
    beta_d = pars[6]
    sigma_d = pars[7]
    nu = pars[8]
    xi = pars[9]
    rho_x = pars[10]
    B0 = pars[16]
    B1 = pars[17]
    
    xnext = row[0]
    ddecnext = row[1]
    weight = row[2]
    K = len(deltavec)
  
    Ezm = B0 + B1*nu*xi/(1-rho_x)
    k0 = np.log(np.exp(Ezm)+1) - Ezm*np.exp(Ezm)/(np.exp(Ezm)+1)
    k1 = np.exp(Ezm)/(np.exp(Ezm)+1)
    
    glogmrs = ((np.repeat(ddecnext,K)-(np.ones(K)+phi*(deltavec-np.ones(K)))*b/deltavec-(1-a)*b*hvec)/(1-b*hvec))
    nacount = np.sum(glogmrs<0)*weight
    glogmrs[glogmrs<0] = np.nan
    if(~np.isnan(glogmrs).all()):
        mrs = rho*np.nanmean(glogmrs**(-gamma))*weight
    else:
        mrs = np.nan
    return np.array([mrs,np.exp(k1*B1*xnext-(-k0+B0-k1*B0-alpha_d-sigma_d*sigma_d/2+(B1-beta_d)*statevar))*mrs,nacount])

def EmrsEmrsx(pars,hyperpars,deltavec,hvec,statevar): #returns 3 columns with future x, future deltadeltaec, weights
    # gamma = pars[3]
    nu = pars[8]
    xi = pars[9]
    rho_x = pars[10]
    mu = pars[11]
    sigma_a = pars[12]
    sigma = pars[13]
    omega_hat = pars[14]
    sigma_hat = pars[15]
  
    zpoismax = int(max(stats.poisson.ppf(hyperpars["statePmax"],rho_x*statevar/xi),5))
    GLweights = np.average(np.power(np.transpose(np.tile(glquadtable[:,0],(zpoismax+1,1))),(np.tile(np.repeat(nu-1,zpoismax+1)+range(zpoismax+1),(np.size(glquadtable,0),1))))/special.gamma(np.tile(np.repeat(nu,zpoismax+1)+range(zpoismax+1),(np.size(glquadtable,0),1))),
                              axis=1,weights=stats.poisson.pmf(range(zpoismax+1),rho_x*statevar/xi))*glquadtable[:,1]

    [Emrs,Emrsx,nacount] = np.array([0,0,0])
    
    for i in range(np.size(glquadtable,0)):
        GLw = glquadtable[i,0]
        # GLw = glquadtable[i,0]/(exp(gamma*(gamma-1)*sigma*sigma/2)-1)
        Jmax = int(stats.poisson.ppf(hyperpars["jPmax"],GLw))
        Jhatmax = int(stats.poisson.ppf(hyperpars["jPmax"],omega_hat))
        jetaaggcnext = np.array([(j,jh,ghquadtable[ghind,0],ghquadtable[ghind,1],ghquadtable[ghind,2]) for j in range(Jmax+1) for jh in range(Jhatmax+1) for ghind in range(np.size(ghquadtable,0))])
        jprobsvec = stats.poisson.pmf(range(Jmax+1),GLw)
        jhatprobsvec = stats.poisson.pmf(range(Jhatmax+1),omega_hat)
        weightcompon = np.array([(jprobsvec[j]*jhatprobsvec[jh]*ghquadtable[ghind,3]) for j in range(Jmax+1) for jh in range(Jhatmax+1) for ghind in range(np.size(ghquadtable,0))])

        xddecnext = list(np.transpose(np.vstack([np.repeat(glquadtable[i,0],np.size(jetaaggcnext,0)),
                                                     np.exp(mu + sigma_a*jetaaggcnext[:,4] + np.sqrt(jetaaggcnext[:,0])*sigma*jetaaggcnext[:,2] - jetaaggcnext[:,0]*sigma*sigma/2 + np.sqrt(jetaaggcnext[:,1])*sigma_hat*jetaaggcnext[:,3] - jetaaggcnext[:,1]*sigma_hat*sigma_hat/2),
                                                     weightcompon/stats.poisson.cdf(Jmax,GLw)/stats.poisson.cdf(Jhatmax,omega_hat)*GLweights[i]])))    
        EmrsExmrsgrid = np.vstack([mrsxmrs(row,pars,deltavec,hvec,statevar) for row in xddecnext])

        reweight = np.sum(np.array(xddecnext)[~np.isnan(EmrsExmrsgrid[:,0]),2])
        Emrs,Emrsx,nacount = [Emrs,Emrsx,nacount] + np.nansum(EmrsExmrsgrid,0)/reweight
    
    return Emrs,Emrsx,nacount



#############################################
#SECTION 4: Moment and penalty calculation
#############################################
def moment_penalty(pars,hyperpars,empiricalmoments):
    print(pars)
    # a = pars[0]
    # b = pars[1]
    # phi = pars[2]
    # gamma = pars[3]
    # rho = pars[4]
    alpha_d = pars[5]
    beta_d = pars[6]
    sigma_d = pars[7]
    nu = pars[8]
    xi = pars[9]
    rho_x = pars[10]
    mu = pars[11]
    sigma_a = pars[12]
    sigma = pars[13]
    omega_hat = pars[14]
    sigma_hat = pars[15]
    B0 = pars[16]
    B1 = pars[17]
    Tt = hyperpars["Tt"] # Number of periods
    B = hyperpars["B"] # Burn-in phase
    K = hyperpars["qmcXsize"] # Number of simulations
  
    xgrid = qmcstategrid(pars,hyperpars)
    aggcgrid = qmcaggcgrid(pars,hyperpars)
    Emrs = np.zeros((Tt,K))
    Exmrs = np.zeros((Tt,K))
    nacount = np.zeros((Tt,K))
    for i in range(K):
        deltagrid = qmcdeltagrid(pars,hyperpars,xgrid[:,i])
        hgrid = hgridfun(pars,aggcgrid[:,i],deltagrid)
        # if __name__ == '__main__':
        #     pool = mp.Pool(int(os.environ['SLURM_JOB_CPUS_PER_NODE']))
        #     EmrsExmrsgrid = pool.starmap(EmrsEmrsx,[(pars,hyperpars,deltagrid[t,:],hgrid[t,:],xgrid[t,i]) for t in range(Tt)])
        #     pool.close()
        #     pool.join()
        EmrsExmrsgrid = [EmrsEmrsx(pars,hyperpars,deltagrid[t,:],hgrid[t,:],xgrid[t,i]) for t in range(Tt)]
        Emrs[:,i] = np.array(EmrsExmrsgrid)[:,0]
        Exmrs[:,i] = np.array(EmrsExmrsgrid)[:,1]
        nacount[:,i] = np.array(EmrsExmrsgrid)[:,2]
    
    Emrs_trim = np.delete(Emrs,range(B),0)
    Exmrs_trim = np.delete(Exmrs,range(B),0)
    nacount_trim = np.delete(nacount,range(B),0)
    
    Ex = nu*xi/(1-rho_x)
    Vx = nu*xi*xi/(1-rho_x)/(1-rho_x)
    MUx = (2*nu*xi*xi/(1-rho_x*rho_x*rho_x))*(1+(3*rho_x/(1-rho_x)*(1+(rho_x/(1-rho_x)))))
    Ew = Ex
    Vw = Vx
    MUw = MUx
    # repar = 1/(exp(gamma*(gamma-1)*sigma*sigma/2)-1)
    # Ew = repar*Ex
    # Vw = repar*repar*Vx
    # MUw = (repar**3)*MUx
    Ezm = B0 + B1*nu*xi/(1-rho_x)
    k0 = np.log(np.exp(Ezm)+1) - Ezm*np.exp(Ezm)/(np.exp(Ezm)+1)
    k1 = np.exp(Ezm)/(np.exp(Ezm)+1)
    rfmat = np.ones((Tt-B,K))/Emrs_trim
    rfautocors = np.zeros(K)
    for i in range(K):
        [rfautocors[i],_] = stats.pearsonr(rfmat[range(1,Tt-B),i],rfmat[range(Tt-B-1),i])
    
    moments_pen = np.zeros(18)
    moments_pen[0] = mu
    moments_pen[1] = sigma_a
    moments_pen[2] = alpha_d + beta_d*Ex
    moments_pen[3] = np.sqrt(beta_d*beta_d*Vx + sigma_d*sigma_d)
    moments_pen[4] = beta_d*beta_d*rho_x*Vx/(beta_d*beta_d*Vx+sigma_d*sigma_d)
    moments_pen[5] = -sigma*sigma/2*Ew - sigma_hat*sigma_hat/2*omega_hat
    moments_pen[6] = (sigma*sigma + (sigma**4)/4)*Ew + (sigma**4)/4*Vw + (sigma_hat*sigma_hat + (sigma_hat**4)/4)*omega_hat
    moments_pen[7] = (-3*(sigma**4)/2 - (sigma**6)/8)*Ew - (3*(sigma**4)/2 + 3*(sigma**6)/8)*Vw - (sigma**6)/8*MUw - (3*(sigma_hat**4)/2 + (sigma_hat**6)/8)*omega_hat
    moments_pen[8] = np.average(rfmat)
    moments_pen[9] = np.average(np.std(rfmat,axis=0))
    moments_pen[10] = np.average(rfautocors)
    moments_pen[11] = B0 + B1*Ex
    moments_pen[12] = B1*np.sqrt(Vx)
    moments_pen[13] = rho_x
    moments_pen[14] = k0 + (k1-1)*B0 + alpha_d + (beta_d + (k1-1)*B1)*Ex
    moments_pen[15] = np.sqrt((k1*k1*B1*B1 + (beta_d-B1)*(beta_d-B1))*Vx + 2*k1*B1*(beta_d-B1)*rho_x + sigma_d*sigma_d)
    moments_pen[16] = (k1*B1*(beta_d-B1)*(1+rho_x*rho_x) + (k1*k1*B1*B1 + (beta_d-B1)*(beta_d-B1))*rho_x)*Vx/((k1*k1*B1*B1+(beta_d-B1)*(beta_d-B1))*Vx+2*k1*B1*(beta_d-B1)*rho_x+sigma_d*sigma_d)
    
    moments_pen[17] = hyperpars["Bpenalty"]*np.sum(Exmrs_trim-np.ones((Tt-B,K))) + hyperpars["napenalty"]*np.sum(nacount_trim)
    
    momentweights = np.ones(18)
    momentweights[[8,14]] = [10,10]
    
    print(datetime.datetime.now())
    print(sum(np.array((moments_pen-np.append(empiricalmoments,0))*momentweights)**2))
    print(np.sum(Exmrs_trim-np.ones((Tt-B,K))))
    print(np.sum(nacount_trim))
    return np.array(moments_pen-np.append(empiricalmoments,0))*momentweights


#############################################
#SECTION 5: Reparametrisation
#############################################
def depar_fun(repars):
    pars = copy.deepcopy(repars)
    pars[3] = np.exp(pars[3]/(1-pars[3]))
    pars[[5,7,8,9,10,11,12,13,14,15]] = pars[[5,7,8,9,10,11,12,13,14,15]]/(1-pars[[5,7,8,9,10,11,12,13,14,15]])
    pars[[6,16,17]] = np.log(pars[[6,16,17]]/(1-pars[[6,16,17]]))
    return pars

def repar_fun(pars):
    repars = copy.deepcopy(pars)
    repars[3] = np.log(repars[3])/(1+np.log(repars[3]))
    repars[[5,7,8,9,10,11,12,13,14,15]] = repars[[5,7,8,9,10,11,12,13,14,15]]/(1+repars[[5,7,8,9,10,11,12,13,14,15]])
    repars[[6,16,17]] = np.exp(repars[[6,16,17]])/(1+np.exp(repars[[6,16,17]]))
    return repars

def mom_habit(repars):
    pars = depar_fun(repars)
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_nohabit(repars):
    pars = depar_fun(np.concatenate((np.array([.99,0,.5]),repars)))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_nohabit_fix(repars):
    pars = depar_fun(np.concatenate((np.array([.99,0,.5]),repars[0:8],myempiricalmoments[[0,1]],repars[8:13])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_inthabit_fix(repars):
    pars = depar_fun(np.concatenate((np.array([.99,0.05,1]),repars[0:8],myempiricalmoments[[0,1]],repars[8:13])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_exthabit_fix(repars):
    pars = depar_fun(np.concatenate((np.array([.99,0.05,0]),repars[0:8],myempiricalmoments[[0,1]],repars[8:13])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_inthabit_emp(repars):
    pars = depar_fun(np.concatenate((repars[0:2],[1],repars[2:10],myempiricalmoments[[0,1]],repars[10:15])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_exthabit_emp(repars):
    pars = depar_fun(np.concatenate((repars[0:2],[0],repars[2:10],myempiricalmoments[[0,1]],repars[10:15])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)

def mom_mixhabit_emp(repars):
    pars = depar_fun(np.concatenate((repars[0:11],myempiricalmoments[[0,1]],repars[11:16])))
    return moment_penalty(pars,myhyperpars,myempiricalmoments)


#############################################
#SECTION 6: Initialisation
#############################################
mypars = np.array([
  0.8,  # a 0
  0.02,  # b 1
  0.2,  # phi 2
  6.343,  # gamma 3
  0.93,  # rho 4
  0.001,  # alpha_d 5
  -40.1,  # beta_d 6
  0.02,  # sigma_d 7
  1.4,  # nu 8
  0.08,  # xi 9
  0.876,  # rho_x 10
  0.008,  # mu 11
  0.004,  # sigma_a 12
  0.0718,  # sigma 13
  0.110,  # omega_hat 14
  0.0623,  # sigma_hat 15
  2, # B0 16
  5  # B1 17
])

myrepars = repar_fun(mypars)
myrepars_nohabit_fix = myrepars[[3,4,5,6,7,8,9,10,13,14,15,16,17]]

mynewpars = np.array([ 9.90000000e-01,  0.00000000e+00,  5.00000000e-01,  5.24619336e+00,
  9.48564796e-01,  2.57790053e-02, -7.13138621e-01,  3.13737509e-02,
  1.49573296e+00,  1.98734470e-03,  9.23005315e-01,  3.97393964e-03,
  8.33150804e-03,  2.48308494e-01,  8.54166196e-02,  5.37916070e-02,
  3.81372274e+00, -7.05747995e-01])
mynewrepars = repar_fun(mynewpars)

mynewrepars_nohabit = mynewrepars[3:18]
mynewrepars_nohabit_fix = mynewrepars[[3,4,5,6,7,8,9,10,13,14,15,16,17]]
mynewrepars_inthabit_emp = mynewrepars[[0,1,3,4,5,6,7,8,9,10,13,14,15,16,17]]
mynewrepars_exthabit_emp = mynewrepars[[0,1,3,4,5,6,7,8,9,10,13,14,15,16,17]]
mynewrepars_mixhabit_emp = mynewrepars[[0,1,2,3,4,5,6,7,8,9,10,13,14,15,16,17]]

myhyperpars = {
  "Tt":5, #number of periods
  "B":2, #burn-in period
  "qmcXsize":3, #number of simulated aggregate trajectories
  "qmcDsize":3, #number of simulated individual trajectories
  "zmax":10, #terms in Poisson weighted sum of gamma distributions for statevar cdf
  "jPmax":1-1e-3, #cut-off probability for possible next-period outcomes of Poisson variables in delta 
  "statePmax":1-1e-3, #cut-off probability for possible next-period outcomes of Poisson variables in state variable generation
  "Bpenalty":1, #pentalty weight parameter for deviations from the Euler equation
  "napenalty":1 #pentalty weight parameter for households dropping out of the model
}

myempiricalmoments = np.loadtxt($(emperical_moments_path))


#############################################
#SECTION 7: And now, we fly
#############################################


print(datetime.datetime.now().time())
# print(pounders.minimize_pounders_np(mom_nohabit_fix, myrepars_nohabit_fix, (np.repeat(0,13),np.repeat(1,13)),init_tr=.001))
print(optimize.least_squares(mom_inthabit_emp, mynewrepars_inthabit_emp, bounds=(0,1)))
print(datetime.datetime.now().time())
"""

# ╔═╡ ceabbac0-32c1-4824-b4d5-be9b5ac99eee
ghquadtable_path = joinpath(split(@__FILE__, '#')[1] * ".assets", "ghquadtable.csv")

# ╔═╡ 4c57beba-2f1e-49df-b6bd-39d72ccd8ef9
emperical_moments_path = joinpath(split(@__FILE__, '#')[1] * ".assets", "empiricalmoments.txt")

# ╔═╡ 60b85416-0ab5-490a-a892-38b498a78467
md"""
## Macro ast-match helpers
"""

# ╔═╡ 5228df12-aa05-4f0b-b3ae-7fef5a1a02cd
function mis_match(needle, haystack)
	throw("Mismatch `$needle` vs `$haystack`")
end

# ╔═╡ 6982e67c-bb73-4cbc-bbe7-f2570015defe
get_simple_spread_placeholder(expr) = let
	if expr.head == :$ && expr.args[1] isa Expr && expr.args[1].head === :...
		expr.args[1].args[1]
	else
		nothing
	end
end

# ╔═╡ 2746f2a3-ca37-4b93-85e8-33a6f2cec308
function get_spread_placeholder(expr)
	if !(expr isa Expr) return nothing end

	placeholder = get_simple_spread_placeholder(expr)
	if placeholder ≠ nothing
		return placeholder
	else
		if length(expr.args) == 1
			return get_spread_placeholder(expr.args[1])
		else
			return nothing
		end
	end
end

# ╔═╡ 65f595ca-62f4-45e2-a464-86c0c814c931
is_spread_placeholder(expr) = get_spread_placeholder(expr) ≠ nothing

# ╔═╡ 164f041c-add7-4887-8813-662db4bf8c4d
flatten_spread_placeholder(expr) = let
	if !is_spread_placeholder(expr)
		expr
	else
		name = get_simple_spread_placeholder(expr)
		if name ≠ nothing
			Expr(:$, name)
		else
			Expr(
				flatten_spread_placeholder(expr.head),
				map(flatten_spread_placeholder, expr.args)...
			)
		end
	end		
end

# ╔═╡ 554b2d6f-aaf0-416a-9abe-d40291501d08
function match(needle, haystack, result=Dict())
	if !(haystack isa Expr)
		if needle ≠ haystack
			mis_match(needle, haystack)
		end
		return result
	end
	
	if haystack isa Expr && haystack.head == :$
		result[haystack.args[1]] = needle
		return result
	end
	
	if !(needle isa Expr)
		mis_match(needle, haystack)
	end
	
	if haystack.head ≠ needle.head
		mis_match(needle, haystack)
	end
	
	haystacks = filter(haystack.args) do x !(x isa LineNumberNode) end
	needles = filter(needle.args) do x !(x isa LineNumberNode) end
	
	needles = if !isempty(haystacks) &&  is_spread_placeholder(haystacks[end])
		name = get_spread_placeholder(haystacks[end])
		required_length = length(haystacks) - 1

		sub_haystack = flatten_spread_placeholder(haystacks[end])
		rest_match = needles[(required_length + 1):end]
		result[name] = map(rest_match) do sub_needle
			match(sub_needle, sub_haystack)[name]
		end
		
		if length(needle.args) < required_length
			mis_match(needles, haystacks)
		end
		needles[1:required_length]
	else
		if length(needles) ≠ length(haystacks)
			mis_match(needles, haystacks)
		end
		needles
	end

	for (needle_arg, haystack_arg) in zip(needles, haystacks)
		match(needle_arg, haystack_arg, result)
	end
	return result
end

# ╔═╡ 6c08f96f-0ce8-4ec3-a0b3-73d46c299c88
function wrap_let_with_if(let_statement)
	result = match(
		let_statement,
		@identity let $var = $(expression)
			$(expressions...)
		end
	)
	
	result_var = esc(result[:var])
	expression = esc(result[:expression])
	
	quote
		let $(result_var) = $(expression)
			if $(result_var) ≠ false && $(result_var) ≠ nothing
				$(map(esc, result[:expressions])...)
			end
		end
	end
end

# ╔═╡ ef17db01-dbd9-481f-825b-58b9731bc84a
@eval macro $(:if)(let_statement)
	wrap_let_with_if(let_statement)
end

# ╔═╡ c87b6293-74b3-4442-af70-f96a4fcdbda2
macro match_ast(needle, haystack)
	try
		match(needle, haystack)
	catch
		nothing
	end
end

# ╔═╡ d125bfce-e798-4762-b6c4-193b4b7ac92a
match_ast(needle, haystack) = try match(needle, haystack) catch e nothing end

# ╔═╡ e7d050b8-1866-4494-a8e9-ed3abf7b077e
let
	match_ast(
		@identity(import thing),
		@identity(import $(value))
	)
end

# ╔═╡ 450e89ee-5dd0-48f6-813d-465ecb62674a
let
	match_ast(
		@identity(import asd.asd.asd.asdasd),
		@identity(import $(thing).$(value...))
	)
end

# ╔═╡ 8cff04f5-1c22-4735-8dac-811b613a83b2
let
	match_ast(
		@identity(import package.thing),
		@identity(import $(package).$(value))
	)
end

# ╔═╡ 4af01502-155c-48d7-8e2b-133ff96684b1
let
	match_ast(
		@identity(import repo.package: name as x),
		@identity(import $(hey...): $(wow) as $(wiii))
	)
end

# ╔═╡ b38c12dc-3f29-45ba-926b-b58a5d4136b0
@py import opensourceeconomics.estimagic: estimagic.optimization.tao_optimizers as module_name2

# ╔═╡ 64520db8-f563-4962-ad2b-ee22e4f9932c
@identity import petsc4py

# ╔═╡ 7ee4c4f4-afea-4e7c-b0b2-ff4001a418ac
@py import petsc4py

# ╔═╡ d2b6361b-f545-44c4-84cd-77b74167b1b8
@py import opensourceeconomics.estimagic: estimagic.optimization.tao_optimizers as module_name2

# ╔═╡ Cell order:
# ╠═eb791876-812f-11eb-0a62-f1011dd01e1e
# ╠═479fe42d-c183-4c2d-800d-42ab11a41b36
# ╠═aba3f7a1-acd1-4c9c-9dea-782ba1477d49
# ╠═749d4ed1-1005-42e9-862c-601692d2841f
# ╠═2d27684f-7cba-462d-bac9-8710fed05825
# ╠═5fa34023-0c92-457c-ba58-acaab4dd6bd8
# ╠═e7d050b8-1866-4494-a8e9-ed3abf7b077e
# ╠═450e89ee-5dd0-48f6-813d-465ecb62674a
# ╠═8cff04f5-1c22-4735-8dac-811b613a83b2
# ╠═4af01502-155c-48d7-8e2b-133ff96684b1
# ╠═3abf129b-ce82-4fa4-bacc-d3bb69c6a45a
# ╠═12cfab00-a4eb-4fd2-9c3a-45ecd665ee55
# ╠═df0025c5-9c70-4a11-8dcf-d080d3e7fe4b
# ╠═824258ab-258e-4570-ae94-e8eebb375c93
# ╠═f32d33c7-3fa6-4331-804d-710abb7ce896
# ╠═b4d1ac2d-f110-40f7-828f-3548b43b9bd4
# ╠═b38c12dc-3f29-45ba-926b-b58a5d4136b0
# ╠═d2b6361b-f545-44c4-84cd-77b74167b1b8
# ╠═7ee4c4f4-afea-4e7c-b0b2-ff4001a418ac
# ╠═3eb02c1d-0167-4bbd-a661-4b647212af79
# ╠═210d6115-e6ab-4067-b5fa-ee0ddda369b4
# ╠═8cedaaf3-e862-46d5-b37c-2a3cb5699518
# ╠═d7e8b1d6-cdd1-466a-a885-0c40835981a9
# ╠═ef017c39-4c0b-464b-94aa-98238b856927
# ╠═70a3af6e-7872-4b3a-aeb3-f657b04f91a5
# ╠═8aecaac6-3475-450c-abe0-793079078f69
# ╠═6b1b63e5-b4bc-46c1-a7a7-d7d8530173be
# ╠═1ee7d3d4-16e0-45ce-ab66-bfbfc0cad0c8
# ╠═1e2dd1f4-3c9b-4d6e-a52c-11c204220884
# ╠═e28ef9bd-eab0-4836-815b-c0d7465f4b99
# ╠═5af71d47-e8fc-4198-bb68-b29f8f39ae0f
# ╠═ec80a7a5-9268-4591-bc43-be806a433c7a
# ╟─95991bdf-500d-4199-bd83-e32d57a3903c
# ╟─276a9a45-ef96-455e-a9e4-9a0258f1566c
# ╟─d573b4f9-0f81-4615-95a0-f83485cf3ef7
# ╟─4b342c7d-e82d-43c1-8888-eed9fd59236f
# ╠═8f512850-89ff-4ec2-985d-22b83db13360
# ╠═b3250d58-726a-44e9-8c1f-4a89053cf27e
# ╠═3510ed8f-dbdf-4558-be0c-adb480562d32
# ╠═8b010349-4fd7-487a-a39d-755493dadef9
# ╠═dc8a3bbc-5b00-4150-b128-ab5645fc45de
# ╠═de0757f0-f20e-464d-9c8c-fa29d28ca44b
# ╠═79ecba06-1a0a-48e1-8757-7329e6e56231
# ╠═561fe73b-7838-461d-a1eb-308a056e03e4
# ╠═64520db8-f563-4962-ad2b-ee22e4f9932c
# ╠═ceabbac0-32c1-4824-b4d5-be9b5ac99eee
# ╠═4c57beba-2f1e-49df-b6bd-39d72ccd8ef9
# ╟─60b85416-0ab5-490a-a892-38b498a78467
# ╟─5228df12-aa05-4f0b-b3ae-7fef5a1a02cd
# ╟─6982e67c-bb73-4cbc-bbe7-f2570015defe
# ╟─2746f2a3-ca37-4b93-85e8-33a6f2cec308
# ╟─65f595ca-62f4-45e2-a464-86c0c814c931
# ╟─164f041c-add7-4887-8813-662db4bf8c4d
# ╟─554b2d6f-aaf0-416a-9abe-d40291501d08
# ╟─6c08f96f-0ce8-4ec3-a0b3-73d46c299c88
# ╟─ef17db01-dbd9-481f-825b-58b9731bc84a
# ╟─c87b6293-74b3-4442-af70-f96a4fcdbda2
# ╟─d125bfce-e798-4762-b6c4-193b4b7ac92a
