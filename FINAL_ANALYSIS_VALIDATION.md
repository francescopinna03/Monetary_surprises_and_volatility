# Verifiche dell'implementazione

Verifica effettuata il 10 settembre 2026 sul commit base `af799bae170d1ecfc3be6aefcc74a8111c06b816`, con modifiche locali non committate nel solo clone. La run di validazione è stata eseguita prima del commit della PR; gli hash del codice eseguito restano nel manifest.

- 15 test Python superati. Coprono endpoint, barre mancanti e duplicate, zero BV, DST asimmetrico, cambi di orario BCE, rilasci ai bordi, covarianza CR1, invarianza alle unità del wild, gate di rango/numerosità, ricostruzione JK, Holm, partial R², campione appaiato e rifiuto di build/certificazioni non validi.
- Build dai dati reali completato: 219 file effettivamente necessari al periodo, 3.273.396 barre, 13.575 root-day selezionati e 27.150 righe di fase. Il fingerprint comprende tutti i 222 file cleaned disponibili, anche quelli fuori dal sottoinsieme caricato.
- Registro di 114 meeting, 4 radici, 2 fasi: 912 righe. Ogni radice-fase ha 114 finestre complete e 111 osservazioni con OIS1Y disponibile. Le esclusioni ulteriori per shock, log, storia e modello restano nei registri di campione.
- Confronto con gli output certificati preesistenti: oltre 6.500 finestre per fase sullo stesso contratto. Massimo scarto assoluto per RV/BV pre e post circa `1.0e-16`. Dettaglio in `Raw/Certification/final_analysis_window_reconstruction_check.csv`.
- Runner completo terminato con 999 repliche wild e 499 repliche per i diagnostici di storia/potenza. Ha prodotto 992 righe di test di fase e 16 test di media, con audit di rotazioni e leave-top-K. La sensibilità PR alle possibili notizie USA ha prodotto ulteriori 16 test, con 80–85 cluster a seconda di K.
- La sensibilità USA appaiata PR–PC si arresta: rimangono 4–5 meeting, sotto il gate di 30. Il filtro considera ogni potenziale coincidenza delle 08:30 e non un calendario verificato. Questo esito non dimostra assorbimento delle notizie USA.
- MATLAB e Octave non disponibili nell'ambiente di verifica. I file MATLAB sono stati revisionati e il driver/self-test è fornito, ma **il rerun MATLAB dello shrinkage non è stato eseguito**. La riuscita del runner Python non equivale a una certificazione d'esecuzione MATLAB.

Ambiente della run completa: Python 3.12.14, NumPy 2.3.5, pandas 2.2.3, SciPy 1.17.0. Seed 20260910. Stato `complete_conditional_inference`. Il wild condiziona agli indicatori e al layer normale stimato; non integra l'incertezza del primo stadio. I numeri qui riportati certificano esecuzione e supporto dei dati, non nuove conclusioni strutturali.

I manifest completi, i registri di ogni modello e le tabelle si rigenerano con `freeze` e `estimate` secondo `FINAL_ANALYSIS_PROTOCOL.md`. Lo snapshot pubblico contiene disponibilità, orari e nomi sorgente, senza prezzi né intensità delle sorprese.

## Rerun MATLAB dell'11 settembre 2026

Le run esterne `Monetary_surprises_FULL_4IvvOA` e `Monetary_surprises_FULL_rqjB5J`, sul commit `9b54c1c`, completano gli Steps 1–15 in MATLAB R2025b Update 3. I nove file dei coefficienti coincidono byte per byte. Le 228 finestre fx/gg hanno cinque rendimenti ciascuna; massimo scarto fra RV di finestra e ricostruzione dalle barre `3.524e-19`. Lo shrinkage sceglie l'indice 1, cioè la penalizzazione più forte della banda 1-SE, per tutti e tre gli outcome. Questo verifica lo Step 14 storico, non ancora il rerun con la selezione congelata pre-PR.

Entrambe le run si arrestano allo Step 17: lo Step 16 registra `median_bar_count_too_small` e non produce il pannello BNS. La correzione mantiene la soglia di sei barre, registra BV come bloccata e instrada soltanto RV al pannello di stato, controllando gli hash degli input. Include `Quasi_markov_input_self_test` per file residui, gate bloccato/passato, pannelli mancanti e hash cambiati. La sintassi shell/Python e i confini della ripresa sono verificati; il nuovo self-test MATLAB deve essere eseguito sulla macchina dell'utente. `Run_resume_after_bns.sh` lo esegue prima di riprendere dallo Step 16 e conserva log e codice della ripresa nello ZIP.

## Ripresa completata dell'11 settembre 2026

L'archivio `Monetary_surprises_FULL_rqjB5J_finish_20260911_182722_5429_results.zip` termina con `current_stage=complete` ed `exit_code=0`. Il self-test Quasi-Markov, gli Step 16-27, la batteria Python e il rebuild ausiliario MATLAB sono completati.

I 23 file della batteria Python sono identici prima e dopo il rebuild (999 repliche wild, 499 di potenza). Le 228 finestre PR MATLAB usano gli stessi contratti del build Python; massimo scarto RV `1.247e-17`. Lo shrinkage sceglie l'indice 1 per i tre outcome. BNS resta bloccato con cinque rendimenti per finestra.

Step 28 supera il gate dati (165/165 contratti), ma nessun punto della griglia 20-120 supera la calibrazione. Restano 100 meeting per fase, con 300 transizioni PR e 700 PC. Decisione `blocked_before_sbb`: i gate successivi non eseguiti sono arresti previsti.

Restano dichiarati l'inferenza condizionale, il calendario USA non verificato e la risoluzione insufficiente dei 896 test Holm con 999 repliche. Questa nota supera le precedenti verifiche ancora pendenti e non modifica la specifica statistica. Gli output storici e finali hanno provenienze distinte. Gli archivi con dati di mercato restano separati dal repository.
