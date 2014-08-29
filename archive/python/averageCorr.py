#!/home/kmtu/local/anaconda3/bin/python
import argparse
import h5py
import numpy as np
from itertools import accumulate

parser = argparse.ArgumentParser(description="Average oneTwoDecompose correlation")
parser.add_argument('corrData', nargs='+', help="correlation data files to be averaged <oneTwoDecompose.corr.h5>")
parser.add_argument('-o', '--out', help="output file, default = 'corr.ave<num>.h5'")
args = parser.parse_args()

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
  return idx_r * size - ([0]+list(accumulate(range(4))))[idx_r] + idx_c - idx_r

numMD = len(args.corrData)
if (args.out == None):
  outFilename = 'corr.ave' + str(numMD) + '.h5'
else:
  outFilename = args.out if args.out.split('.')[-1] == 'h5' else args.out + '.h5'

isTimeLagsChanged = False
# sum the NDCesaroData
for n, data in enumerate(args.corrData):
  with h5py.File(data, 'r') as f:
    print("reading " + data)
    if (n == 0):
      numMol = f.attrs['numMol']
      numIonTypes = numMol.size
      numIonTypePairs = (numIonTypes*(numIonTypes+1)) / 2;
      charge = f.attrs['charge']
      timeLags = f['timeLags'][:]
      autoCorrN = np.zeros([numMD, numIonTypes, timeLags.size])
      crossCorrN = np.zeros([numMD, numIonTypePairs, timeLags.size])
      volumeN = np.zeros([numMD])

    if (f['timeLags'].size != timeLags.size):
      isTimeLagsChanged = True
      if (f['timeLags'].size < timeLags.size):
        timeLags = f[timeLags][...]
        autoCorrN = autoCorrN[..., :timeLags.size]
        crossCorrN = crossCorrN[..., :timeLags.size]

    volumeN[n] = f.attrs['cell'].prod()
    autoCorrN[n, :, :] += f['autoCorr'][:, :timeLags.size]
    for i in range(numIonTypes):
      for j in range(i, numIonTypes):
        if (i == j):
          crossCorrN[n, zipIndexPair2(i, j, numIonTypes), :] += \
              f['crossCorr'][zipIndexPair(i, j, numIonTypes), :timeLags.size]
        else:
          crossCorrN[n, zipIndexPair2(i, j, numIonTypes), :] += \
              (f['crossCorr'][zipIndexPair(i, j, numIonTypes), :timeLags.size] +
              f['crossCorr'][zipIndexPair(j, i, numIonTypes), :timeLags.size]) / 2

if (isTimeLagsChanged):
  print("Note: the maximum timeLags are different among the corr files\n"
        "      it is now set to {} ps".format(timeLags[-1]))

autoCorr = np.mean(autoCorrN, axis=0)
crossCorr = np.mean(crossCorrN, axis=0)
volume = np.mean(volumeN, axis=0)
autoCorr_std = np.std(autoCorrN, axis=0)
crossCorr_std = np.std(crossCorrN, axis=0)
volume_std = np.std(volumeN, axis=0)
autoCorr_err = autoCorr_std / np.sqrt(numMD)
crossCorr_err = crossCorr_std / np.sqrt(numMD)
volume_err = volume_std / np.sqrt(numMD)

with h5py.File(args.corrData[0], 'r') as f, h5py.File(outFilename, 'w') as outFile:
  for (name, value) in f.attrs.items():
    if (name != 'cell'):
      outFile.attrs[name] = value

  outFile['timeLags'] = timeLags
  outFile['volume'] = volume
  outFile['volume_err'] = volume_err
  outFile['autoCorr'] = autoCorr
  outFile['crossCorr'] = crossCorr
  outFile['autoCorr_err'] = autoCorr_err
  outFile['crossCorr_err'] = crossCorr_err

  outFile['timeLags'].dims.create_scale(outFile['timeLags'], 't')
  outFile['autoCorr'].dims[1].attach_scale(outFile['timeLags'])
  outFile['autoCorr_err'].dims[1].attach_scale(outFile['timeLags'])
  outFile['crossCorr'].dims[1].attach_scale(outFile['timeLags'])
  outFile['crossCorr_err'].dims[1].attach_scale(outFile['timeLags'])

print("File is output as: " + outFilename)
