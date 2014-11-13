#!/home/kmtu/local/anaconda3/bin/python
import argparse
import h5py
import numpy as np
import matplotlib.pyplot as plt
import matplotlib as mpl
from matplotlib.colors import Normalize
from matplotlib import cm
import itertools as it

parser = argparse.ArgumentParser(description="Plot decomposed correlation")
parser.add_argument('corrData', help="correlation data file <corr.h5>")
parser.add_argument('-o', '--out', default='corr', help="output figure base filename, default = 'corr'")
parser.add_argument('--threshold', type=float, default=0, help="RDF threshold for plotting sdCorr, default = 0")
parser.add_argument('--color', nargs='*', help="manually assign line color for each auto and cross terms. "
                                    "<auto1>...<autoN> <cross11>...<cross1N> <cross22>...<cross2N> .. <crossNN>")
parser.add_argument('--label', nargs='*', help="manually assign label for each component. <mol1>...<molN>")
parser.add_argument('--nosd', action='store_true', help="no-SD mode, i.e. one-two only mode")
parser.add_argument('-p', '--plugin', nargs='*', help="plugin files which will be executed at the end")
args = parser.parse_args()

threshold = args.threshold

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
    outFilename = 'corr-nosd'
  else:
    outFilename = 'corr'
else:
  outFilename = args.out

class Const:
  """
  Defines some constants
  """
  nm2AA = 10

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
  return idx_r * size - ([0]+list(it.accumulate(range(4))))[idx_r] + idx_c - idx_r

with h5py.File(args.corrData, 'r') as f:
  timeLags = f['timeLags'][...]
  nCorr = f['nCorr'][...]  # nm^2 / ps^2
  volume = f['volume'][...]
  numMol = f.attrs['numMol'][...]
  numIonTypes = numMol.size
  numIonTypePairs = (numIonTypes*(numIonTypes+1)) // 2;
  if (not args.nosd):
    rBins = f['rBins'][...]
    sdCorr = f['sdCorr'][...]  # nm^2 / ps^2
    rho = f['rho'][...]

# validate arguments
if (args.color is not None):
  assert(len(args.color) == numIonTypes + numIonTypePairs )
  mpl.rcParams['axes.color_cycle'] = args.color

def connectLabel(label):
  return label[0] + '-' + label[1]

if (args.label is not None):
  assert(len(args.label) == numIonTypes)
  label = args.label
else:
  label = ['{}'.format(i+1) for i in range(numIonTypes)]
label += [connectLabel(l) for l in it.combinations_with_replacement(label, 2)]

# plot nCorr
nCorr2 = np.empty([numIonTypes + numIonTypePairs, timeLags.size])
nCorr2[:numIonTypes] = nCorr[:numIonTypes]
for i in range(numIonTypes):
  for j in range(i, numIonTypes):
    idx1_ij = numIonTypes + zipIndexPair(i, j, numIonTypes)
    idx2 = numIonTypes + zipIndexPair2(i, j, numIonTypes)
    if (i == j):
      nCorr2[idx2] = nCorr[idx1_ij]
    else:
      idx1_ji = numIonTypes + zipIndexPair(j, i, numIonTypes)
      nCorr2[idx2] = (nCorr[idx1_ij] + nCorr[idx1_ji]) / 2

rc = {'font': {'size': 34,
               'family': 'serif',
               'serif': 'Times'},
      'text': {'usetex': True},
      'legend': {'fontsize': 34},
      'axes': {'labelsize': 34,
               'titlesize': 34},
      'xtick': {'labelsize': 34,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5},
      'ytick': {'labelsize': 34,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5},
      'lines': {'linewidth': 3},
      'savefig': {'transparent': True}
     }

for key in rc:
  mpl.rc(key, **rc[key])

xlabelpad = 5
ylabelpad = 0.5
reflinewidth = 1.5
spineLineWidth = 1.6

figsize1 = (8, 5)
format='eps'

lineStyle = ['--'] * numIonTypes + ['-'] * numIonTypePairs
plt.figure(figsize=figsize1)
plt.gca().axhline(0, linestyle=':', color='black', linewidth=reflinewidth)
for i, corr in enumerate(nCorr2*Const.nm2AA**2):
  if (i == 3):
    plt.plot(timeLags, corr, label=label[i], linestyle=lineStyle[i], color='g')
#  plt.plot(timeLags, corr, label=label[i], linestyle=lineStyle[i])
    
leg = plt.legend()
plt.xlim(xmax=0.4)
plt.xticks([0, 0.1, 0.2, 0.3, 0.4])
plt.xlabel(r'$t$\ \ (ps)', labelpad=xlabelpad)
plt.ylabel(r'$C_{IL}^{(2)}(t)$\ \ (\AA$^2$ ps$^{-2}$)', labelpad=ylabelpad)
#plt.tight_layout()

ax = plt.gca()
for sp in ax.spines.values():
  sp.set_linewidth(spineLineWidth)

plt.savefig(outFilename + '.oneTwo.' + format, bbox_inches="tight", pad_inches=0.20)

if (not args.nosd):
  # plot sdCorr
  rc = {'font': {'size': 46,
                 'family': 'serif',
                 'serif': 'Times'},
        'text': {'usetex': True},
        'legend': {'fontsize': 46},
        'axes': {'labelsize': 46,
                 'titlesize': 50},
        'xtick': {'labelsize': 46,
                  'major.pad': 10,
                  'major.size': 8,
                  'major.width': 1.5},
        'ytick': {'labelsize': 46,
                  'major.pad': 10,
                  'major.size': 8,
                  'major.width': 1.5},
        'lines': {'linewidth': 3}
       }

  for key in rc:
    mpl.rc(key, **rc[key])

  xlabelpad = 5
  ylabelpad = 0.5 
  clabelpad = 20
  spineLineWidth = 1.6
  figsize3 = (40, 9)

  sdCorr2 = np.empty([numIonTypePairs, rBins.size, timeLags.size])
  rho2 = np.empty([numIonTypes * (numIonTypes + 1) / 2, rBins.size])
  for i in range(numIonTypes):
    for j in range(i, numIonTypes):
      if (i == j):
        rho2[zipIndexPair2(i, j, numIonTypes)] = rho[zipIndexPair(i, j, numIonTypes)]
        sdCorr2[zipIndexPair2(i, j, numIonTypes)] = sdCorr[zipIndexPair(i, j, numIonTypes)]
      else:
        rho2[zipIndexPair2(i, j, numIonTypes)] = (rho[zipIndexPair(i, j, numIonTypes)] +
                                                  rho[zipIndexPair(j, i, numIonTypes)]) / 2
        sdCorr2[zipIndexPair2(i, j, numIonTypes)] = (sdCorr[zipIndexPair(i, j, numIonTypes)] +
                                                       sdCorr[zipIndexPair(j, i, numIonTypes)]) / 2

  density = numMol / volume
  dr = rBins[1] - rBins[0]
  dv = 4 * np.pi * rBins**2 * dr
  vol = volume
  rho_Vdv = rho2
  rho_V = rho_Vdv / dv
  rho_dv = rho_Vdv / vol
  rho = rho_V / vol
  g = rho / np.array([d1 * d2 for (e1, d1) in enumerate(density)
                              for (e2, d2) in enumerate(density) if e2 >= e1]
                    )[:, np.newaxis]

  class CustomNormalize(Normalize):
      def __init__(self, vmin=None, vmax=None, vanchor=None, clip=False, canchor=0.5):
          self.vanchor = vanchor
          self.canchor = canchor
          Normalize.__init__(self, vmin, vmax, clip)

      def __call__(self, value, clip=None):
          # I'm ignoring masked values and all kinds of edge cases to make a
          # simple example...
          x, y = [self.vmin, self.vanchor, self.vmax], [0, self.canchor, 1]
          return np.ma.masked_array(np.interp(value, x, y))

  smallRegion = []
  for rdf in g:
    smallRegion.append(next(i for i, v in enumerate(rdf) if v >= 1))
  print("smallRegion =", smallRegion)

  sdCorr2_masked = np.ma.masked_where(np.ones_like(sdCorr2) *
                      np.array([c if j <= smallRegion[i] else False
                                 for j, c in enumerate(g[i] < threshold)])[np.newaxis, :, np.newaxis], sdCorr2)

  nm2AA = 10

  tmin, tmax, tstep = 0, 201, 1
  rmin, rmax, rstep = 19, 71, 1
  T, R = np.meshgrid(timeLags[tmin:tmax:tstep], rBins[rmin:rmax:rstep] * nm2AA)
  cmap = cm.get_cmap('RdYlBu_r')

  for i, sd in enumerate(sdCorr2_masked):
    vmin, vmax = (np.nanmin(sdCorr2_masked[i, rmin:rmax:rstep, tmin:tmax:tstep]) * nm2AA**2,
                  np.nanmax(sdCorr2_masked[i, rmin:rmax:rstep, tmin:tmax:tstep]) * nm2AA**2)
    norm = CustomNormalize(vanchor=0, canchor=0.42, vmin=vmin, vmax=vmax)
    plt.figure()
    c = plt.contourf(T, R, sd[rmin:rmax:rstep, tmin:tmax:tstep] * nm2AA**2,
                     32, norm=norm, cmap=cmap)
  #  plt.contour(T, R, sd[rmin:rmax:rstep, tmin:tmax:tstep] * nm2AA**2, [0], colors='black')
    ax = plt.gca()
    ax.set_xlabel(r'$t$\ \ (ps)', labelpad=xlabelpad)
    ax.set_ylabel(r'$r$\ \ (\AA)', labelpad=ylabelpad)
    ax.set_title(label[numIonTypes + i])
    cb = plt.colorbar(c)
    cb.set_label(r'$c_{IL}^{(2)}(t;r)$\ \ (\AA$^2$ ps$^{-2}$)')
#    plt.tight_layout()
    plt.savefig(outFilename + '.sd' + str(i) + '.' + format, bbox_inches="tight", pad_inches=0.15)

  vmin, vmax = (np.nanmin(sdCorr2_masked[:, rmin:rmax:rstep, tmin:tmax:tstep]) * nm2AA**2,
                np.nanmax(sdCorr2_masked[:, rmin:rmax:rstep, tmin:tmax:tstep]) * nm2AA**2)
  norm = CustomNormalize(vanchor=0, canchor=0.42, vmin=-1.2, vmax=1.8)
  bounds = np.arange(-0.20, 1.801, 0.1)
  fig, axs = plt.subplots(1, numIonTypePairs, sharex=True, sharey=True, figsize=figsize3)
  for i, (ax, sd) in enumerate(zip(axs.flat, sdCorr2_masked)):
    c = ax.contourf(T, R, sd[rmin:rmax:rstep, tmin:tmax:tstep] * nm2AA**2,
                    bounds, norm=norm, cmap=cmap)
  #  ax.contour(T, R, sd[rmin:rmax:rstep, tmin:tmax:tstep] * nm2AA**2, [0], colors='black')
    ax.set_xlabel(r'$t$\ \ (ps)', labelpad=xlabelpad)
#    ax.set_title(label[numIonTypes + i])
    plt.sca(ax)
    plt.title(label[numIonTypes + i], y=1.02)
    plt.xticks([0, 0.1, 0.2, 0.3, 0.4])
    if (i == 0):
      ax.set_ylabel(r'$r$\ \ (\AA)', labelpad=ylabelpad)

#  plt.subplots_adjust(left=None, bottom=None, right=None, top=None, wspace=None, hspace=None)
#  plt.subplots_adjust(left=0.05, bottom=0.15, right=1.05, wspace=0.07)
  cb = plt.colorbar(c, ax=axs.ravel().tolist(), ticks=np.arange(0, 1.801, 0.4), pad=0.01)
  cb.set_label(r'$c_{IL}^{(2)}(t;r)$\ \ (\AA$^2$ ps$^{-2}$)', labelpad=clabelpad)
#  plt.tight_layout()

  for sp in cb.ax.spines.values():
    sp.set_linewidth(spineLineWidth)
  for ax in axs:
    for sp in ax.spines.values():
      sp.set_linewidth(spineLineWidth)

  plt.savefig(outFilename + '.sd.' + format, bbox_inches="tight", pad_inches=0.15)

#plot c(t;r) at given r
rc = {'font': {'size': 34,
               'family': 'serif',
               'serif': 'Times'},
      'text': {'usetex': True},
      'legend': {'fontsize': 34},
      'axes': {'labelsize': 34,
               'titlesize': 34},
      'xtick': {'labelsize': 34,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5},
      'ytick': {'labelsize': 34,
                'major.pad': 10,
                'major.size': 8,
                'major.width': 1.5},
      'lines': {'linewidth': 3},
      'savefig': {'transparent': True}
     }

for key in rc:
  mpl.rc(key, **rc[key])

xlabelpad = 5
ylabelpad = 0.5

figsize1 = (8, 5)

rr = [29, 37, 45]
for ri in rr:
  plt.figure(figsize=figsize1)
  plt.gca().axhline(0, linestyle=':', color='black', linewidth=reflinewidth)
  #for i, corr in enumerate(nCorr2*Const.nm2AA**2):
  #  if (i == 3):
  #    plt.plot(timeLags, corr, label=label[i], linestyle=lineStyle[i], color='r')
  #  plt.plot(timeLags, corr, label=label[i], linestyle=lineStyle[i])
    
  for i, sd in enumerate(sdCorr2_masked):
  #  c = ax.contourf(T, R, sd[rmin:rmax:rstep, tmin:tmax:tstep] * nm2AA**2,
  #                  bounds, norm=norm, cmap=cmap)
    if (i==1):
      plt.plot(timeLags[tmin:tmax:tstep], sd[ri, tmin:tmax:tstep]* nm2AA**2, label=label[numIonTypes+i], linestyle=lineStyle[numIonTypes+i], color='r')

  #leg = plt.legend()
  plt.xlim(xmax=0.4)
  plt.ylim(bottom=-0.3, top=2)
  plt.xticks([0, 0.1, 0.2, 0.3, 0.4])
  plt.yticks([0, 1, 2])
  plt.xlabel(r'$t$\ \ (ps)', labelpad=xlabelpad)
  plt.ylabel(r'$c^{(2)}_{IL}(t; r)$\ \ (\AA$^2$ ps$^{-2}$)', labelpad=ylabelpad)
  #plt.tight_layout()

  ax = plt.gca()
  for sp in ax.spines.values():
    sp.set_linewidth(spineLineWidth)

  plt.savefig(outFilename + '.oneTwo.r' + str(ri) + '.' + format, bbox_inches="tight", pad_inches=0.20)


plt.ion()
#plt.show()

# execute plugin scripts
if (args.plugin is not None):
  for plug in args.plugin:
    with open(plug) as f:
      code = compile(f.read(), plug, 'exec')
      exec(code)
