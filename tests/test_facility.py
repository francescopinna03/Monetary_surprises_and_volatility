import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import pandas as pd
from facility_archive import split_archive, frozen_copy, digest
from facility_run import shrinkage_summary
import facility_run
from confirmation_analysis.inventory import search_roots


def raw(directory, symbol):
    p = directory/f'{symbol}_intraday-5min_historical-data-09-12-2026.csv'
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(b'Raw bytes, including the full contract lifespan; not parsed\n')
    return p


class ArchiveTests(unittest.TestCase):
    def test_split_preserves_bytes_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); data = base/'data'
            generation = raw(data/'Raw/Barchart_futures', 'ggh13')
            confirmation = raw(generation.parent, 'ggz12')
            expected = confirmation.read_bytes()
            preview = split_archive(data, base/'preview')
            self.assertTrue(confirmation.exists()); self.assertEqual(preview['status'],'dry_run')
            result = split_archive(data, base/'apply',True)
            moved = data/'Raw/Barchart_futures_confirmation'/confirmation.name
            self.assertEqual(moved.read_bytes(),expected)
            self.assertFalse(confirmation.exists()); self.assertTrue(generation.exists())
            self.assertEqual(result['moved'],1)
            self.assertEqual(split_archive(data,base/'again',True)['moved'],0)

    def test_collision_stops_before_any_move(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data=base/'data'; source=data/'Raw/Barchart_futures'
            raw(source,'ggh13'); old=raw(source,'ggz12'); raw(source,'ggm12')
            target=raw(data/'Raw/Barchart_futures_confirmation','ggz12')
            with self.assertRaisesRegex(ValueError,'collision'):
                split_archive(data,base/'out',True)
            self.assertTrue(old.exists()); self.assertTrue(target.exists())
            self.assertEqual(len(list(source.glob('*.csv'))),3)

    def test_unknown_and_symlink_csv_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data=base/'data'; source=data/'Raw/Barchart_futures'
            p=raw(source,'ggh13'); unknown=source/'mystery.csv'; unknown.write_text('x')
            with self.assertRaisesRegex(ValueError,'Unrecognized'):
                split_archive(data,base/'out',True)
            unknown.unlink(); (source/'ggh12_intraday-5min_historical-data-09-12-2026.csv').symlink_to(p)
            with self.assertRaisesRegex(ValueError,'unaliased'):
                split_archive(data,base/'out',True)

    def test_inventory_is_closed_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); target=base/'Raw/Barchart_futures_confirmation'; target.mkdir(parents=True)
            with patch('confirmation_analysis.inventory.Path.home', side_effect=AssertionError('No home discovery')):
                self.assertEqual(search_roots(base),[target.resolve()])
            with self.assertRaisesRegex(ValueError,'exclusive'):
                search_roots(base,target,discover_home=True)


def frozen_fixture(base, date='2013-01-10'):
    data=base/'data'; repo=base/'repo'; build=base/'build'
    build.mkdir(); (repo/'Raw/Certification').mkdir(parents=True)
    spec=repo/'Raw/Certification/final_analysis_spec_v1.json'; spec.write_text('{}')
    source=data/'Output/cleaned/ggh13_clean.csv'; source.parent.mkdir(parents=True); source.write_text('generation prices')
    (build/'preferred_contracts.csv').write_text(f'event_date\n{date}\n2026-03-19\n')
    (build/'specification.json').write_text('{}')
    hashes={'Output/cleaned/ggh13_clean.csv':digest(source),'specification':digest(spec)}
    with (build/'input_hashes.csv').open('w',newline='') as stream:
        w=csv.writer(stream); w.writerow(['relative_path','sha256']);w.writerows(hashes.items())
    (build/'status.json').write_text(json.dumps(dict(status='frozen',schema_version='final_analysis_v1',
        table_hashes={'preferred_contracts.csv':digest(build/'preferred_contracts.csv')},
        specification_sha256=digest(build/'specification.json'),source_hashes=hashes)))
    return data,repo,build,source


class FrozenCopyTests(unittest.TestCase):
    def test_missing_matlab_still_packages_failure_without_raw_access(self):
        with tempfile.TemporaryDirectory() as tmp:
            facility=Path(tmp).resolve(); repo=facility/'Monetary_surprises_clone'; repo.mkdir()
            arguments=['facility_run.py','--facility',str(facility),'--mode','calibration',
                       '--data-root',str(facility/'no_raw_directory')]
            with patch.object(facility_run,'REPO',repo), patch('sys.argv',arguments), \
                    patch.object(facility_run,'matlab_binary',side_effect=FileNotFoundError('MATLAB unavailable')), \
                    patch.object(facility_run,'split_archive',side_effect=AssertionError('No empirical archive access')):
                self.assertEqual(facility_run.main(),2)
            self.assertEqual(len(list(facility.glob('*_results.zip'))),1)
            status=json.loads(next((facility/'runs').glob('*/status.json')).read_text())
            self.assertFalse(status['confirmation_freeze_performed'])
            self.assertEqual(status['stages'][0]['status'],'blocked_or_failed')

    def test_exact_inputs_only_and_2026_exclusion_recorded(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data,repo,build,source=frozen_fixture(base)
            raw(data/'Raw/Barchart_futures_confirmation','ggh00')
            (source.parent/'stale_confirmation_clean.csv').write_text('not for this run')
            dest=base/'run/Econometrics_data'
            frozen_copy(data,build,dest,repo)
            self.assertEqual(digest(source),digest(dest/'Output/cleaned/ggh13_clean.csv'))
            self.assertFalse((dest/'Raw/Barchart_futures_confirmation').exists())
            self.assertFalse((dest/'Output/cleaned/stale_confirmation_clean.csv').exists())
            report=json.loads((dest.parent/'generation_inputs.json').read_text())
            self.assertEqual(report['excluded_later_event_dates'],['2026-03-19'])

    def test_leakage_rejected_before_copying_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data,repo,build,source=frozen_fixture(base,'2012-12-06')
            with self.assertRaisesRegex(ValueError,'GENERATION_LEAKAGE'):
                frozen_copy(data,build,base/'destination',repo)
            self.assertFalse((base/'destination').exists())

    def test_mismatch_does_not_overwrite_and_fallback_is_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data,repo,build,source=frozen_fixture(base)
            recovery=base/'old'; old=recovery/'Output/cleaned/ggh13_clean.csv'
            old.parent.mkdir(parents=True); old.write_bytes(source.read_bytes()); source.write_text('changed')
            with self.assertRaisesRegex(ValueError,'Missing or changed'):
                frozen_copy(data,build,base/'failed',repo)
            dest=base/'run/Econometrics_data'; frozen_copy(data,build,dest,repo,recovery)
            self.assertEqual(source.read_text(),'changed')
            self.assertEqual(digest(dest/'Output/cleaned/ggh13_clean.csv'),digest(old))

    def test_repository_recovery_fallback_is_hash_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data,repo,build,source=frozen_fixture(base)
            bundled = repo/'Raw/Certification/generation_recovery_20260911/Output/cleaned/ggh13_clean.csv'
            bundled.parent.mkdir(parents=True)
            bundled.write_bytes(source.read_bytes())
            source.unlink()
            dest=base/'run/Econometrics_data'
            frozen_copy(data,build,dest,repo)
            self.assertEqual(digest(dest/'Output/cleaned/ggh13_clean.csv'),digest(bundled))

            bundled.write_text('tampered')
            with self.assertRaisesRegex(ValueError,'Missing or changed'):
                frozen_copy(data,build,base/'tampered',repo)

    def test_different_hash_index_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); data,repo,build,source=frozen_fixture(base)
            (build/'input_hashes.csv').write_text('relative_path,sha256\n')
            with self.assertRaisesRegex(ValueError,'differs'):
                frozen_copy(data,build,base/'out',repo)

    def test_shrinkage_report_compares_rules_on_identical_cv_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp)
            t=pd.DataFrame(dict(depvar=['RV']*3, **{'lambda':[20.,5.,1.]},
                cv_mse=[1.1,1.,1.05],cv_se=[.2,.2,.2],lambda_chosen=[20.]*3))
            t.to_csv(base/'shrinkage_cv_path.csv',index=False)
            shrinkage_summary(base,base/'comparison.csv')
            self.assertEqual(pd.read_csv(base/'comparison.csv').penalty_ratio.iloc[0],20.)
            t['lambda_chosen']=1.;t.to_csv(base/'shrinkage_cv_path.csv',index=False)
            with self.assertRaisesRegex(ValueError,'1-SE rule violated'):
                shrinkage_summary(base,base/'bad.csv')


if __name__ == '__main__':
    unittest.main()
