import json
import tempfile
import unittest
from zipfile import ZipFile
from pathlib import Path
from unittest.mock import patch
import numpy as np
import pandas as pd
from scipy.integrate import quad
from final_analysis.models import clustered
from confirmation_analysis.cones import cone_functionals, surface_design, surface_contrasts
from confirmation_analysis.inference import wild_contrast
from confirmation_analysis.protocol import (parse_contract, resolution_gate, clock_reference,
    generation_mask, assert_generation_events, digest)
from confirmation_analysis.audit import audit_file, calendar_review, audit
from confirmation_analysis.bridge import read_generation_build
from confirmation_analysis.inventory import discover


class ConfirmationTests(unittest.TestCase):
    def test_cone_closed_form_and_rotated_domain(self):
        a = np.array([[2., -.7], [-.7, 1.]])
        f = cone_functionals(a)
        def q(phi):
            d = np.array([np.cos(phi), np.sin(phi)])
            return d @ a @ d
        self.assertAlmostEqual(f['mp'], quad(q, -np.pi/2, 0)[0]/(np.pi/2), places=12)
        self.assertAlmostEqual(f['cbi'], quad(q, 0, np.pi/2)[0]/(np.pi/2), places=12)
        theta = .37
        r = np.array([[np.cos(theta), -np.sin(theta)], [np.sin(theta), np.cos(theta)]])
        b = r.T @ a @ r
        def rotated(phi):
            d = r.T @ np.array([np.cos(phi), np.sin(phi)])
            return d @ b @ d
        self.assertAlmostEqual(quad(rotated, -np.pi/2, 0)[0]/(np.pi/2), f['mp'], places=12)
        self.assertNotAlmostEqual(cone_functionals(b)['mp'], f['mp'], places=5)

    def test_cone_basis_factor_two_and_state(self):
        beta = np.array([1., 2., 1., -.7, .2, .3, .4, -.1])
        c = surface_contrasts()
        s = surface_contrasts(slope=True)
        self.assertAlmostEqual((c @ beta)[2], -4/np.pi * beta[3])
        self.assertAlmostEqual((s @ beta)[0], (.3+.4)/2 + 2/np.pi*.1)
        x = surface_design([2.], [3.], [.5])
        np.testing.assert_allclose(x, [[1, 4, 9, 12, .5, 2, 4.5, 6]])
        with self.assertRaises(ValueError):
            cone_functionals([[1, 2], [0, 1]])

    def test_linear_wild_cr1_and_batching(self):
        rng = np.random.default_rng(7)
        g = np.repeat(np.arange(50), 2)
        x = np.column_stack([np.ones(100), rng.normal(size=(100, 2))])
        y = x @ [1., -.6, .2] + rng.normal(size=50)[g] + rng.normal(size=100)*.1
        c = np.array([0., 1., -.5])
        r = wild_contrast(y, x, g, c, 399, np.random.default_rng(9), batch_size=17)
        r2 = wild_contrast(y, x, g, c, 399, np.random.default_rng(9), batch_size=128)
        fit = clustered(y, x, g)
        self.assertAlmostEqual(r['estimate'], c @ fit['beta'], places=12)
        self.assertAlmostEqual(r['se_cr1'], np.sqrt(c @ fit['V'] @ c), places=12)
        self.assertEqual(r['p_wild'], r2['p_wild'])
        self.assertGreater(r['p_wild'], .95)
        opposite = wild_contrast(y, x, g, -c, 399, np.random.default_rng(9))
        self.assertLess(opposite['p_wild'], .05)

    def test_resolution(self):
        self.assertFalse(resolution_gate(999, 896)['pass_resolution'])
        self.assertTrue(resolution_gate(19999, 2)['pass_resolution'])

    def test_year_zero_and_bounds(self):
        for yy, expected in [('00', 2000), ('12', 2012), ('99', 1999)]:
            self.assertEqual(parse_contract(f'ggh{yy}_intraday-5min_historical-data-09-12-2026.csv', 2026)['contract_year'], expected)
        with self.assertRaises(ValueError):
            parse_contract('ggh27_intraday-5min_historical-data-09-12-2026.csv', 2026)

    def test_historical_clocks(self):
        t = clock_reference().set_index('date')
        self.assertEqual(t.loc['2004-04-01', 'offset_hours'], 8)
        self.assertEqual(t.loc['2004-11-04', 'offset_hours'], 7)
        self.assertEqual(t.loc['2007-11-01', 'offset_hours'], 6)

    def test_generation_separation(self):
        self.assertEqual(generation_mask(pd.Series(['2012-12-31', '2013-01-01', '2025-12-31', '2026-01-01'])).tolist(), [False, True, True, False])
        with self.assertRaisesRegex(ValueError, 'LEAKAGE'):
            assert_generation_events(pd.Series(['2011-06-01', '2013-01-01']))

    def test_bridge_rejects_confirmation_before_loading_outcomes(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            (p/'windows.csv').write_text('trade_date,is_event,BV_post\n2001-01-04,True,DO_NOT_READ\n')
            (p/'ea_source.csv').write_text('event_date,phase\n2001-01-04,PR\n')
            (p/'specification.json').write_text('{}')
            (p/'status.json').write_text(json.dumps(dict(status='frozen', code_hashes={},
                specification_sha256=digest(p/'specification.json'),
                table_hashes={name: digest(p/name) for name in ['windows.csv', 'ea_source.csv']})))
            original = pd.read_csv
            with patch('confirmation_analysis.bridge.pd.read_csv', wraps=original) as reader:
                with self.assertRaisesRegex(ValueError, 'LEAKAGE'):
                    read_generation_build(p)
                self.assertEqual(reader.call_count, 1)
                self.assertEqual(reader.call_args.kwargs['usecols'], ['trade_date', 'is_event'])

    def test_audit_does_not_read_price_columns(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'ggh00_intraday-5min_historical-data-09-12-2026.csv'
            p.write_text('Time,Latest,Volume\n01/05/2000 06:40,DO_NOT_READ,10\n01/05/2000 06:45,DO_NOT_READ,20\n')
            result, sessions = audit_file(p, parse_contract(p.name, 2026))
            self.assertEqual(result['status'], 'metadata_ok_prices_not_checked')
            self.assertEqual(len(sessions), 1)
            self.assertEqual(sessions[0]['n_bars'], 2)

    def test_source_pc_not_certified_as_conference(self):
        t = pd.DataFrame({'event_date': ['2001-05-23'], 'phase': ['PC'],
            'source_datetime': pd.to_datetime(['2001-05-23 14:30'])})
        r = calendar_review(t)
        pc = r[r.phase.eq('PC')].iloc[0]
        self.assertTrue(pc.source_window_present)
        self.assertEqual(pc.actual_phase_present, '')
        self.assertTrue(pc.actual_pc_requires_specific_evidence)
        self.assertEqual(pc.weekday, 'Wednesday')

    def test_empty_download_is_not_metadata_ok(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/'fxh11_intraday-5min_historical-data-09-11-2026.csv'
            p.write_text('Time,Latest,Volume\nDownloaded from Barchart.com,,\n')
            result, sessions = audit_file(p, parse_contract(p.name, 2026))
            self.assertEqual(result['n_rows'], 0)
            self.assertEqual(result['status'], 'review')
            self.assertIn('no_timestamped_bars', result['flags'])
            self.assertEqual(sessions, [])

    def test_discovery_reports_archives_without_opening_payloads(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            raw = p/'raw'; raw.mkdir()
            out = p/'out'; out.mkdir()
            name = 'ggh00_intraday-5min_historical-data-09-11-2026.csv'
            (raw/name).write_text('DO_NOT_READ')
            with ZipFile(raw/'deep.zip', 'w') as z:
                z.writestr('deep/'+name, 'DO_NOT_READ')
                z.writestr('unrelated.csv', 'DO_NOT_READ')
            with patch.object(ZipFile, 'open', side_effect=AssertionError('Archive payload accessed')):
                folders, result = discover([raw, raw], out)
            self.assertEqual([p.resolve() for p in folders], [raw.resolve()])
            self.assertEqual(result['n_candidate_csv_paths'], 1)
            self.assertEqual(result['n_archives_with_candidate_names'], 1)
            self.assertFalse(result['archived_csv_payloads_read'])

    def test_empty_inventory_audit_retains_event_root_phase_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            raw = p/'Raw/Barchart_futures'; raw.mkdir(parents=True)
            ea = p/'Raw/EA-EMPD'; ea.mkdir()
            (raw/'fxh11_intraday-5min_historical-data-09-11-2026.csv').write_text('Time,Latest,Volume\n')
            t = pd.DataFrame({'Date_time': ['2000-01-05 13:45'], 'Event_type': ['GC_PR'],
                'OIS_1M': [np.nan], 'OIS_3M': [.1], 'OIS_6M': [.1], 'OIS_1Y': [.1], 'STOXX50E': [.2]})
            t.to_excel(ea/'EA-EMPD.xlsx', sheet_name='EA-EMPD', index=False)
            result = audit(p, [raw], p/'out')
            self.assertFalse(result['confirmation_outcomes_computed'])
            self.assertEqual(result['n_registry_rows'], 8)
            self.assertEqual(result['n_expected_contracts_present'], 1)
            self.assertEqual(result['n_expected_contracts_with_bars'], 0)
            self.assertEqual(result['n_raw_files_without_bars'], 1)
            self.assertFalse(result['archive_coverage_certified'])
            coverage = pd.read_csv(p/'out/contract_coverage_v2.csv')
            self.assertEqual(coverage.loc[coverage.n_files.eq(1), 'status'].iloc[0], 'no_timestamped_bars')
            with self.assertRaises(FileExistsError):
                audit(p, [raw], p/'out')

    def test_audit_uses_one_primary_copy_for_registry_availability(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            raw_a = p/'a'; raw_a.mkdir()
            raw_b = p/'b'; raw_b.mkdir()
            ea = p/'Raw/EA-EMPD'; ea.mkdir(parents=True)
            name = 'ggh00_intraday-5min_historical-data-09-11-2026.csv'
            content = 'Time,Latest,Volume\n01/05/2000 06:40,DO_NOT_READ,10\n01/05/2000 06:45,DO_NOT_READ,20\n'
            (raw_a/name).write_text(content)
            (raw_b/name).write_text(content.replace(',20', ',21'))
            pd.DataFrame({'Date_time': ['2000-01-05 13:45'], 'Event_type': ['GC_PR'],
                'OIS_1M': [.1], 'OIS_3M': [.1], 'OIS_6M': [.1], 'OIS_1Y': [.1], 'STOXX50E': [.2]}) \
                .to_excel(ea/'EA-EMPD.xlsx', sheet_name='EA-EMPD', index=False)
            result = audit(p, [raw_a, raw_b], p/'out')
            self.assertEqual(result['n_duplicate_candidate_cells'], 1)
            self.assertEqual(result['n_primary_contracts_with_bars'], 1)
            registry = pd.read_csv(p/'out/event_registry_v2.csv')
            self.assertEqual(registry.loc[(registry.root_code=='gg') & (registry.phase=='PR'), 'n_contracts_with_date'].iloc[0], 1)
            sessions = pd.read_csv(p/'out/sessions_v2.csv')
            self.assertIn('input_path', sessions.columns)
            self.assertEqual(sessions.input_path.nunique(), 2)


if __name__ == '__main__':
    unittest.main()
