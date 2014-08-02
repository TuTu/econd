#!/home/kmtu/local/anaconda3/bin/python
import argparse
import h5py
import numpy as np
import matplotlib.pyplot as plt

parser = argparse.ArgumentParser(description="Plot and examine the results from fitSdDCesaro.py and fitNDCesaro.py")
parser.add_argument('-ND', '--NDCesaroFit', help="fitted ND results data file <NDCesaro.fit.h5>")
parser.add_argument('sdDCesaroFit', help="fitted sdD results data file <sdDCesaro.fit.h5>")
parser.add_argument('-o', '--out', default='sdDCesaro.fit', help="output figure base filename, default = 'sdDCesaro.fit'")
parser.add_argument('-T', '--temp', type=float, required=True, help="temperature in K")
args = parser.parse_args()

class Const:
  """
  Defines some constants
  """
  kB = 1.3806488E-23 #(J K-1)
  beta = 1 / (kB * args.temp) #(J-1)
  basicCharge = 1.60217646E-19 #(Coulomb)
  ps = 1.0E-12 #(s)
  nm = 1.0E-9 #(m)

def loadDictFromH5(h5g):
  dict = {}
  def func(k, v):
    dict[k] = v[...]
  h5g.visititems(func)
  return dict

if (args.NDCesaroFit != None):
  with h5py.File(args.NDCesaroFit, 'r') as fND:
    zz = fND['zz'][...]
    ND = loadDictFromH5(fND['ND'])
    volumeND = fND['volume'][...]
    Const.ND2ecSI = Const.beta * Const.basicCharge**2 / (volumeND*(Const.nm**3)) * Const.nm**2 / Const.ps

with h5py.File(args.sdDCesaroFit, 'r') as fSdD:
  charge = fSdD.attrs['charge'][...]
  numMol = fSdD.attrs['numMol'][...]
  numIonTypes = numMol.size
  numIonTypePairs = (numIonTypes*(numIonTypes+1)) / 2;
  rBins = fSdD['rBins'][...]
  zzCross = fSdD['zzCross'][...]
  volumeSdD = fSdD['volume'][...]
  sdDCesaro = fSdD['sdDCesaro'][...]
  sdDCesaro_err = fSdD['sdDCesaro_err'][...]
  rho2 = fSdD['rho2'][...]
  rho2_err = fSdD['rho2_err'][...]
  sdD = loadDictFromH5(fSdD['sdD'])
  sdD_err = loadDictFromH5(fSdD['sdD_err'])
  Const.sdD2ecSI = Const.beta * Const.basicCharge**2 / (volumeSdD*(Const.nm**3)) * Const.nm**2 / Const.ps

density = numMol / volumeSdD

dr = rBins[1] - rBins[0]
dv = 4 * np.pi * rBins**2 * dr

vol = volumeSdD
rho_Vdv = rho2
rho_V = rho_Vdv / dv
rho_dv = rho_Vdv / vol
rho = rho_V / vol
g = rho / np.array([d1 * d2 for (e1, d1) in enumerate(density)
                            for (e2, d2) in enumerate(density) if e2 >= e1]
                  )[:, np.newaxis]

p = []
for i, rdf in enumerate(g):
    p.append(plt.plot(rBins, rdf, label='{}'.format(i)))

plt.ion()
plt.show()
