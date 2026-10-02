# Catena di conferma v2: costruzione protetta, calibrazione, freeze, stima

Stato: implementazione completa della catena. La specifica `final_analysis_spec_v2.json`
resta in bozza finche' `Run_confirmation.sh freeze` non la risolve in `frozen_v2`.
Nessun outcome del campione di conferma e' stato costruito in sviluppo.

Questo documento descrive solo le quattro fasi nuove. Inventario, audit di qualita'
e ponte di generazione restano descritti in `CONFIRMATION_PROTOCOL_V2.md` e
`CONFIRMATION_NEXT_STEPS.md`.

## Decisioni riviste

Le cinque questioni aperte non sono risolte dal codice. `Run_confirmation.sh decisions-template`
scrive `Raw/Certification/confirmation_decisions_v2.json` con le alternative ammissibili e
i campi `reviewer`, `decided_on`, `rationale` vuoti. `load_decisions` rifiuta un file con
scelta assente, scelta non ammissibile, revisore mancante, motivazione mancante o data
mancante. Nessun altro modulo ha un valore di ripiego.

| Chiave | Alternative ammissibili |
|---|---|
| `pc_normal_pre_support` | griglia v1 con endpoint -25..-5, supporto (-30,-5] |
| `slow_state_rule` | media dei cinque precedenti giorni-contratto **non evento** |
| `equity_source_rule` | STOXX50E esterno omogeneo 2000-2012, oppure ibrido fx quando disponibile |
| `secondary_family_rule` | famiglia secondaria della specifica, blocco storico congiunto unico |
| `us_calendar_status` | solo screen di candidati, oppure calendario verificato fornito |

La seconda voce non e' cosmetica. `final_analysis/data.py` calcola `slow5_log_rv` dalla RV
giornaliera dei cinque giorni-contratto precedenti, inclusi i giorni di riunione, e quindi
da outcome post-annuncio di eventi. Nel campione di conferma quella regola leggerebbe
outcome prima del freeze. La regola v2 esclude i giorni evento dal calcolo. La differenza
fra le due regole e' misurata sul campione di **generazione** e riportata in
`slow_state_validation_generation.csv`, mai sul campione di conferma.

## Costruzione protetta

```bash
bash Run_confirmation_calibration.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J" \
  /percorso/confirmation_quality_RUN/quality
```

Esegue `control-build` e poi `calibrate`, e chiude con un report di prontezza. Produce uno
ZIP anche dopo un errore.

`control-build` ricostruisce le finestre dai file grezzi gia' certificati, in **modalita'
cieca**: per una riunione nessun prezzo successivo all'annuncio viene letto. Le righe evento
conservano soltanto la finestra di stato pre-PR, la copertura e l'ammissibilita' certificata.
Una guardia esplicita solleva `BLINDING_VIOLATION` se una qualunque quantita' post-annuncio
di un evento risulta finita. Le tabelle prodotte sono i controlli completi, il registro pre
degli eventi e le covariate EA-EMPD.

Lo strato di continuazione normale v2 differisce dal v1 in due punti dichiarati: nessun
indicatore di regime 2022, che sarebbe identicamente nullo prima del 2013, e origine del
trend al 2000-01-01. Il modulo v1 non e' toccato, cosi' il ponte continua a verificarne gli
hash.

## Calibrazione ex ante

`calibrate` non legge alcun outcome di conferma. Il rumore proviene dai residui
leave-year-out della BV anomala dei giorni-radice **di controllo** del Bund, ricampionati
dentro l'anno solare. Il disegno usa le coordinate esterne EA-EMPD e lo stato pre-PR,
perche' la coordinata Schatz allineata di una riunione e' essa stessa una quantita'
post-annuncio e resta non letta fino al freeze.

Produce due curve di potenza: la dimensione rilevabile delle due ipotesi primarie sulla
griglia `delta_grid`, e il floor del partial R2 storico su `power_partial_r2_grid`, entrambe
con limite inferiore di Wilson al 95% e soglia `power_target`. Il margine calibrato entra
nella specifica congelata accanto al margine scientifico di riferimento, che resta distinto:
una precisione raggiungibile non e' una soglia di trascurabilita' economica.

La dimensione rilevabile e' espressa nella metrica esterna. Il primario congelato usa la
coordinata Schatz allineata: il manifesto lo dichiara e il numero non va letto come una
soglia sulla scala del test primario.

## Freeze

```bash
bash Run_confirmation_final.sh \
  "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J" \
  /percorso/confirmation_quality_RUN/quality \
  /percorso/confirmation_calibration_RUN/build \
  /percorso/confirmation_calibration_RUN/calibration \
  /percorso/confirmation_preparation_RUN/bridge \
  I_HAVE_REVIEWED_THE_FROZEN_SPECIFICATION
```

Il token finale e' obbligatorio. Il freeze e' l'unico punto in cui gli outcome del campione
di conferma vengono costruiti, e non e' reversibile.

Prima di costruire, `freeze` verifica che la calibrazione appartenga a quella costruzione
protetta, che la costruzione protetta appartenga a quell'audit di qualita', che le decisioni
non siano cambiate dopo la costruzione, che il ponte sia una diagnostica di sola generazione
con tabelle intatte, e che entrambe le famiglie con claim superino il gate di risoluzione
`1/(B+1) <= alpha/m`. Con B = 19.999 e m = 2 la soglia di Holm e' 0,025 e il p minimo
raggiungibile 0,00005: il primo rifiuto e' possibile. Una directory di destinazione esistente
viene rifiutata.

La specifica risolta registra la fonte azionaria scelta, il margine calibrato, gli esiti dei
quattro controlli del ponte e i due gate di risoluzione.

## Stima

`estimate` accetta soltanto una build `frozen_v2` con hash di tabelle, specifica e codice
invariati. Produce tre file separati.

`primary_tests.csv` contiene i due test primari: H1, media di cono MP positiva, e H2,
differenza MP meno CBI positiva, entrambi sulla superficie PR del Bund a stato nullo, con
coordinata Schatz allineata, unilaterali, Holm su due. `primary_surface.csv` riporta la
matrice grezza, i funzionali di cono, autovalori e direzione principale: sono invarianti per
rotazione e non sono energie MP/CBI ruotate.

`secondary_tests.csv` contiene la famiglia secondaria dichiarata: modulazione da parte dello
stato, bilaterale, sulla matrice di interazione; le stesse due ipotesi sulla RV anomala; e
le stesse due ipotesi dentro ciascuna delle due epoche. Otto p-value, Holm dentro la
famiglia, etichettati come secondari.

`sensitivity_tests.csv` contiene leave-top-K per energia totale, indicatori alternativi,
radici alternative e lo screen USA sul solo ramo PR. Nessuna correzione simultanea e nessun
claim: l'etichetta `descriptive_no_simultaneous_claim` e' scritta in ogni riga.

L'inferenza resta condizionata agli indicatori misurati e allo strato di continuazione
stimato. Il bootstrap non integra l'incertezza di costruzione degli indicatori.

## Step 28

`Raw/Certification/step28_sbb_specification_extended_calibration.csv` deriva dalla specifica
congelata e ne cambia un solo valore: la griglia di numerosita' arriva a 500 riunioni.
Serve a registrare dove si colloca il campione esteso rispetto ai criteri gia' congelati.

```bash
STEP28_SBB_SPECIFICATION=Raw/Certification/step28_sbb_specification_extended_calibration.csv \
  ./Run_step28_gates.sh /percorso/Econometrics_data
```

E' una calibrazione outcome-free. Nessuna stima SBB, nessun outcome evento. Il risultato va
nella sezione dei limiti, non fra i risultati economici.

## Cosa la catena continua a rifiutare

Il report di prontezza resta bloccante su `external_window_timing` finche' gli orari di
base e di chiusura delle finestre EA-EMPD non sono legati a evidenza di fonte, e su
`us_release_calendar` finche' esiste solo lo screen dei candidati. Uno screen dei giovedi'
alle 8:30 di New York non e' un calendario verificato di rilasci. Queste voci non impediscono
il freeze per costruzione: impediscono di descrivere il risultato come se quelle verifiche
fossero state fatte.
