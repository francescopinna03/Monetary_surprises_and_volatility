import unittest
from pathlib import Path
import json
import tempfile
import numpy as np
import pandas as pd
from final_analysis.data import exact_returns, variation, MINUTE, clocks, candidate_0830, intersects
from final_analysis.models import clustered, wild_test, DesignGate, jk_rotation, holm, residual_partial_r2
from final_analysis.battery import paired

class Windows(unittest.TestCase):
    def test_exact_five_returns_and_bv_identity(self):
        times=np.arange(0,31,5)*MINUTE;prices=np.exp(np.arange(7)*.01)
        r=exact_returns(times,prices,np.arange(5,26,5)*MINUTE)
        np.testing.assert_allclose(r,.01,rtol=0,atol=1e-15)
        self.assertAlmostEqual(variation(r)['RV'],.0005)
        self.assertAlmostEqual(variation(r)['BV'],np.pi/2*.0004)
        prices[-1]=1000
        np.testing.assert_allclose(exact_returns(times,prices,np.arange(5,26,5)*MINUTE),r)
    def test_missing_bar_never_bridged(self):
        times=np.array([0,5,15,20,25])*MINUTE
        r=exact_returns(times,np.exp(np.arange(5)*.01),np.arange(5,26,5)*MINUTE)
        self.assertTrue(np.isnan(r[1:3]).all())
        self.assertTrue(np.isnan(variation(r)['BV']))
    def test_zero_bv_is_observed_not_missing(self):
        self.assertEqual(variation(np.zeros(5))['BV'],0)
        self.assertTrue(np.isnan(variation(np.full(5,np.nan))['BV']))
    def test_duplicate_times_rejected(self):
        with self.assertRaises(ValueError): exact_returns([0,0,MINUTE],np.ones(3),[MINUTE])
    def test_dst_asymmetry_and_schedule_change(self):
        winter=clocks('2023-02-02');spring=clocks('2023-03-16')
        self.assertEqual(winter['PR'].hour,13)
        self.assertEqual(spring['PR'].hour,13)
        self.assertEqual(candidate_0830('2023-02-02').hour,13)
        self.assertEqual(candidate_0830('2023-03-16').hour,12)
        self.assertTrue(intersects(winter['PR'],[5,10,15,20,25],candidate_0830('2023-02-02')))
        self.assertFalse(intersects(spring['PR'],[5,10,15,20,25],candidate_0830('2023-03-16')))
        self.assertEqual(clocks('2022-06-09')['PR'].minute,45)
        self.assertEqual(clocks('2022-07-21')['PR'].minute,15)
    def test_release_on_phase_boundary_is_flagged(self):
        c=clocks('2021-12-16')
        self.assertTrue(intersects(c['PC'],list(range(5,46,5)),candidate_0830('2021-12-16')))

class Inference(unittest.TestCase):
    def setUp(self):
        rng=np.random.default_rng(53);self.g=np.repeat(np.arange(60),2)
        self.X=np.column_stack([np.ones(120),rng.normal(size=(120,3))])
        self.y=self.X@np.array([1,.2,.3,-.1])+rng.normal(size=60)[self.g]+rng.normal(size=120)
    def test_wild_invariant_to_predictor_units(self):
        a=wild_test(self.y,self.X,self.g,[1,2],99,np.random.default_rng(10))
        b=wild_test(self.y,self.X*np.array([1,1e-5,30,2]),self.g,[1,2],99,np.random.default_rng(10))
        self.assertEqual(a[0],b[0]);self.assertAlmostEqual(a[1],b[1],places=10)
        self.assertGreaterEqual(a[0],.01)
    def test_cluster_covariance_matches_sandwich(self):
        f=clustered(self.y,self.X,self.g);X=self.X
        b=np.linalg.lstsq(X,self.y,rcond=None)[0];res=self.y-X@b
        meat=sum(np.outer(X[self.g==g].T@res[self.g==g],X[self.g==g].T@res[self.g==g]) for g in range(60))
        inv=np.linalg.inv(X.T@X);V=(60/59)*(119/116)*inv@meat@inv
        np.testing.assert_allclose(f['V'],V,atol=1e-12)
    def test_rank_and_cluster_gate(self):
        with self.assertRaises(DesignGate):clustered(self.y,np.column_stack([self.X,self.X[:,1]]),self.g)
        with self.assertRaises(DesignGate):clustered(self.y,self.X,self.g%10)
    def test_rotation_reconstruction_every_quantile(self):
        M=self.X[:,1:3]
        for q in [.1,.25,.5,.75,.9]:
            U,C=jk_rotation(M,q);np.testing.assert_allclose(U@C,M,atol=1e-12)
            np.testing.assert_allclose(U.sum(axis=1),M[:,0],atol=1e-12)
            self.assertLess(C[0,1],0);self.assertGreater(C[1,1],0)
    def test_holm_preserves_missing_and_family_size(self):
        np.testing.assert_allclose(holm([.04,.01,.03,np.nan]),[.06,.03,.06,np.nan],equal_nan=True)
    def test_partial_r2_nested_residual_definition(self):
        base=self.X[:,:2];block=self.X[:,2:]
        a=residual_partial_r2(self.y,base,block)
        r0=self.y-base@np.linalg.lstsq(base,self.y,rcond=None)[0]
        r1=clustered(self.y,self.X,self.g)['residual']
        self.assertAlmostEqual(a,(r0@r0-r1@r1)/(r0@r0))
    def test_paired_sample_drops_only_incomplete_root_event_pairs(self):
        t=pd.DataFrame(dict(trade_date=pd.to_datetime(['2020-01-01']*3),root_code=['fx','fx','gg'],phase=['PR','PC','PR'],y=[1,2,3],is_event=True,window_eligible=True))
        p=paired(t,['y'],['fx','gg'])
        self.assertEqual(len(p),2);self.assertTrue(p.root_code.eq('fx').all())

class CertificationGates(unittest.TestCase):
    def test_frozen_build_rejects_code_drift_before_writing(self):
        from final_analysis.run import estimate
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);build=root/'build';build.mkdir();out=root/'result'
            (build/'status.json').write_text(json.dumps(dict(status='frozen',code_hashes={})))
            with self.assertRaisesRegex(ValueError,'Code/spec changed'):
                estimate(root,build,out)
            self.assertFalse(out.exists())
    def test_unresolved_time_certificate_is_rejected(self):
        from final_analysis.data import certify
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);manifest=root/'Output/manifests';manifest.mkdir(parents=True)
            spec=root/'spec.json';spec.write_text('{}')
            pd.DataFrame([dict(status='unresolved')]).to_csv(manifest/'window_semantics_manifest.csv',index=False)
            with self.assertRaisesRegex(ValueError,'Uncertified'):
                certify(root,spec)

if __name__=='__main__':unittest.main()
