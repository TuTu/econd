from decond.tests import analyzer_test as at
import numpy as np

np.seterr(all='raise')
at.test_get_inner_sel()
at.test_new_decond()
at.test_extend_decond()
at.test_fit_decond()
