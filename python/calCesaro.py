#!/home/kmtu/local/anaconda3/bin/python
import argparse
import h5py
import numpy as np
from scipy import integrate
from itertools import accumulate

parser = argparse.ArgumentParser(description="Calcuate no-average Cesaro from corr file")
parser.add_argument('corrData', help="correlation data file. <corr.h5>")
parser.add_argument('--intDelta', type=int, default=1, help="integration delta step. Default = 1")
parser.add_argument('-o', '--out', help="output file, default = 'cesaro.h5'")
parser.add_argument('--nosd', action='store_true', help="no-SD mode, i.e. one-two only mode")
args = parser.parse_args()

if (not args.nosd):
  with h5py.File(args.corrData, 'r') as f:
    try:
      rBins = f['rBins'][...]
    except KeyError as e:
      print("Warning: no 'rBins' dataset is found in", args.corrData)
      print("Automatically change to --nosd mode")
      args.nosd = True

if (args.out is None):
  if (args.nosd):
    outFilename = 'cesaro-nosd.h5'
  else:
    outFilename = 'cesaro.h5'
else:
  outFilename = args.out if args.out.split('.')[-1] == 'h5' else args.out + '.h5'

def zipIndexPair(idx_r, idx_c, size):
  """
  Returns the single index based the row index and column index
  """
  return idx_r * size + idx_c

def zipIndexPair2(idx_r, idx_c, size):
  """
  Returns the single index of a upper-half matrix based the row index and column index

  accepts only the "upper-half" index pair, because cross-correlation should
  be the same for (i,j) and (j,i)
  """
  assert(idx_r <= idx_c)
  return idx_r * size + idx_c - list(accumulate(range(size)))[idx_r]

with h5py.File(args.corrData, 'r') as f:
  print("processing", args.corrData, "...")
  timestep = f.attrs['timestep'][...]
  numMol = f.attrs['numMol'][...]

  timeLags = f['timeLags'][0::args.intDelta]
  nCorr = f['nCorr'][..., 0::args.intDelta]

  if (not args.nosd):
    rBins = f['rBins'][...]
    sdCorr = f['sdCorr'][..., 0::args.intDelta]
    rho = f['rho'][...]

  print("timestep = {}".format(timestep))
  print("numMol = {}".format(numMol))

  numIonTypes = numMol.size

  nDCesaro = np.empty([numIonTypes * (numIonTypes + 3) // 2, timeLags.size])
  # autocorrelation
  nDCesaro[:numIonTypes] = nCorr[:numIonTypes]
  # cross correlation
  for i in range(numIonTypes):
    for j in range(i, numIonTypes):
      idx1_ij = numIonTypes + zipIndexPair(i, j, numIonTypes)
      idx2 = numIonTypes + zipIndexPair2(i, j, numIonTypes)
      if (i == j):
        nDCesaro[idx2, :] = nCorr[idx1_ij, :]
      else:
        idx1_ji = numIonTypes + zipIndexPair(j, i, numIonTypes)
        nDCesaro[idx2, :] = (nCorr[idx1_ij, :] + nCorr[idx1_ji, :]) / 2
  # double integration
  nDCesaro = integrate.cumtrapz(nDCesaro, timeLags, initial = 0)
  nDCesaro = integrate.cumtrapz(nDCesaro, timeLags, initial = 0)

  if (not args.nosd):
    sdDCesaro = np.empty([numIonTypes * (numIonTypes + 1) / 2, rBins.size, timeLags.size])
    rho2 = np.empty([numIonTypes * (numIonTypes + 1) / 2, rBins.size])
    for i in range(numIonTypes):
      for j in range(i, numIonTypes):
        if (i == j):
          rho2[zipIndexPair2(i, j, numIonTypes)] = rho[zipIndexPair(i, j, numIonTypes)]
          sdDCesaro[zipIndexPair2(i, j, numIonTypes)] = sdCorr[zipIndexPair(i, j, numIonTypes)]
        else:
          rho2[zipIndexPair2(i, j, numIonTypes)] = (rho[zipIndexPair(i, j, numIonTypes)] +
                                                       rho[zipIndexPair(j, i, numIonTypes)]) / 2
          sdDCesaro[zipIndexPair2(i, j, numIonTypes)] = (sdCorr[zipIndexPair(i, j, numIonTypes)] +
                                                         sdCorr[zipIndexPair(j, i, numIonTypes)]) / 2
    sdDCesaro = integrate.cumtrapz(sdDCesaro, timeLags, initial = 0)
    sdDCesaro = integrate.cumtrapz(sdDCesaro, timeLags, initial = 0)

  with h5py.File(outFilename, 'w') as outFile:
    for (name, value) in f.attrs.items():
      outFile.attrs[name] = value

    if ('cell' not in f.attrs):
      outFile['volume'] = f['volume'][...]

    outFile['timeLags'] = timeLags
    outFile['nDCesaro'] = nDCesaro
    outFile['timeLags'].dims.create_scale(outFile['timeLags'], 't')
    outFile['nDCesaro'].dims[1].attach_scale(outFile['timeLags'])

    if (not args.nosd):
      outFile['rBins'] = rBins
      outFile['rho2'] = rho2
      outFile['sdDCesaro'] = sdDCesaro
      outFile['rBins'].dims.create_scale(outFile['rBins'], 'r')
      outFile['sdDCesaro'].dims[1].attach_scale(outFile['rBins'])
      outFile['sdDCesaro'].dims[2].attach_scale(outFile['timeLags'])
      outFile['rho2'].dims[1].attach_scale(outFile['rBins'])

  print("File is output as: " + outFilename)
