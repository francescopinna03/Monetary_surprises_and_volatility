import unittest
import numpy as np
import pandas as pd
from confirmation_analysis.cross_epoch import (holm_fixed,symmetric_decomposition,cone_contrast,common_support,target_contrast,wild_t_interval)
from confirmation_analysis.functional_form import degree2_basis,quadratic_angles_radial1,degree1_basis
from Prepare_cross_epoch_inputs import control_slow

class CrossEpochTests(unittest.TestCase):
    def test_missing_p_keeps_family(self):
        np.testing.assert_allclose(holm_fixed([.02,np.nan,.5]),[.06,1.,1.])
    def test_exact_decomposition_and_equal_response(self):
        rng=np.random.default_rng(9)
        dh,dg,bh,bg=rng.normal(size=(4,8))
        r=symmetric_decomposition(dh,dg,bh,bg)
        self.assertAlmostEqual(r['composition']+r['response'],r['total'])
        r=symmetric_decomposition(dh,dg,bh,bh)
        self.assertEqual(r['response'],0.)
        self.assertAlmostEqual(r['composition'],r['total'])
    def test_same_composition_is_all_response(self):
        d=np.arange(8.);a=np.ones(8);b=np.ones(8)*2
        r=symmetric_decomposition(d,d,a,b)
        self.assertEqual(r['composition'],0.)
        self.assertEqual(r['response'],28.)
    def test_same_angle_at_radius_one_and_known_contrast(self):
        a=cone_contrast(degree2_basis);b=cone_contrast(quadratic_angles_radial1)
        np.testing.assert_allclose(a,b,atol=1e-12)
        self.assertAlmostEqual(a[3],-4/np.pi,places=7)
        np.testing.assert_allclose(a[[0,1,2,4,5,6,7]],0,atol=1e-12)
    def test_slow_state_excludes_events_and_current_date(self):
        dates=pd.date_range('2013-01-01',periods=8)
        t=pd.DataFrame({'trade_date':dates,'root_code':'gg','phase':'PR','is_event':[False]*5+[True,False,False],'log_day_rv':[1.,2.,3.,4.,5.,10000.,6.,7.]})
        v=control_slow(t).slow_state_new
        self.assertTrue(np.isnan(v.iloc[4]));self.assertEqual(v.iloc[5],3.)
        self.assertEqual(v.iloc[6],3.);self.assertEqual(v.iloc[7],4.)
    def panel(self,year,offset=0):
        rng=np.random.default_rng(year);n=100
        u=rng.uniform(.1,1,n)+offset;z=rng.uniform(.1,1,n)
        z[::2]*=-1
        return pd.DataFrame({'trade_date':pd.date_range(f'{year}-01-01',periods=n),'u':u,'z':z,'crossfit_state_z':rng.normal(size=n),'crossfit_abnormal_log_BV':rng.normal(size=n)})
    def test_disjoint_amplitudes_fail_support_gate(self):
        _,_,gate=common_support(self.panel(2000),self.panel(2013,offset=10))
        self.assertFalse(gate)
    def test_target_cancels_pure_radial_effect(self):
        t,_,gate=common_support(self.panel(2000),self.panel(2013));self.assertTrue(gate)
        c=target_contrast(degree2_basis,t)
        np.testing.assert_allclose(c[[0,1,2,4,5,6]],0,atol=1e-13)
        self.assertLess(c[3],0)
    def test_axis_never_allocated_to_sector(self):
        h=self.panel(2000);h.loc[0,'u']=0
        t,_,_=common_support(h,self.panel(2013))
        self.assertEqual(t.loc[0,'sector'],'axis');self.assertFalse(t.loc[0,'common_support'])
    def test_wild_interval_invariant_to_column_units(self):
        rng=np.random.default_rng(5);n=70
        x=np.column_stack([np.ones(n),rng.normal(size=n)]);y=x@np.array([.2,.4])+rng.normal(size=n)
        r=wild_t_interval(y,x,np.arange(n),[0,1],199,12)
        xx=x.copy();xx[:,1]*=10
        q=wild_t_interval(y,xx,np.arange(n),[0,10],199,12)
        self.assertAlmostEqual(r['ci95_low'],q['ci95_low'],places=10)
        self.assertAlmostEqual(r['ci95_high'],q['ci95_high'],places=10)

if __name__=='__main__':unittest.main()
