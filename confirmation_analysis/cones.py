import numpy as np


def cone_weights():
    return np.array([[.5, .5, -2 / np.pi], [.5, .5, 2 / np.pi],
                     [0., 0., -4 / np.pi]])


def cone_functionals(matrix):
    a = np.asarray(matrix, float)
    if a.shape != (2, 2) or not np.isfinite(a).all():
        raise ValueError('A must be a finite 2x2 matrix')
    if not np.allclose(a, a.T, rtol=0, atol=1e-12):
        raise ValueError('A must be symmetric')
    return dict(zip(['mp', 'cbi', 'difference'], cone_weights() @ a[[0, 1, 0], [0, 1, 1]]))


def surface_design(u, z, state):
    u, z, state = (np.asarray(x, float) for x in (u, z, state))
    if u.ndim != 1 or u.shape != z.shape or u.shape != state.shape:
        raise ValueError('Coordinates and state must be aligned vectors')
    q = np.column_stack([u*u, z*z, 2*u*z])
    return np.column_stack([np.ones(len(u)), q, state, state[:, None]*q])


def surface_contrasts(slope=False):
    c = np.zeros((3, 8))
    c[:, (5 if slope else 1):(8 if slope else 4)] = cone_weights()
    return c
