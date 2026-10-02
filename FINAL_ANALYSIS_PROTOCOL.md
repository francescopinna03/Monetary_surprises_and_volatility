# Specifica congelata per la nuova stima

Questa implementazione conserva i tre livelli della domanda di ricerca. Il ramo finale parte dal controfattuale di fase; non riapre i gate degli Step 26–28 e non recupera le tabelle di aprile. La specifica è `Raw/Certification/final_analysis_spec_v1.json`. È un congelamento successivo all'audit esplorativo, non una preregistrazione retroattiva: `prior_results_seen=true` resta nel manifest.

## Convenzioni e campione

| Oggetto | Definizione eseguibile |
|---|---|
| PR | Rendimenti con endpoint +5,+10,+15,+20,+25 minuti; supporto effettivo `(PR, PR+25]` |
| PC | Endpoint +5,…,+45; supporto `(PC, PC+45]` |
| Stato e selezione del contratto | Endpoint −55,…,−5 rispetto a PR; supporto `(PR−60, PR−5]` |
| Previsione della continuazione normale | Pre-PR per PR; endpoint PC−25,…,PC−5 per PC, come nel controfattuale di fase esistente |
| Orologio | UTC, timestamp di fine intervallo; `interval_start` richiede lo spostamento di cinque minuti |
| Dati mancanti | Nessun riempimento, interpolazione o rendimento fra barre non consecutive; tutte le coppie richieste devono essere presenti |
| Outcome | BV bipower primaria; RV sensibilità. Si esclude lo zero dal log, senza sostituirlo con una costante |
| Asset | fx/gg primari; fx/gg/hf/hr solo nella sensibilità dichiarata |
| Contratto | Completezza e copertura pre-PR, poi volume pre-PR, infine nome file per risolvere parità; nessuna variabile post-PR entra nel ranking |

RV e BV sono funzioni dello stesso vettore di rendimenti. BV usa `(pi/2) sum(abs(r_j*r_{j-1}))`, senza correzione per M. Con cinque rendimenti PR il linguaggio ammesso è *proxy bipower* e *residuo RV−BV*. Il codice non attribuisce strutturalmente continuo e salti.

Il pre-PC del modello di continuazione può contenere notizie PR. Questo condizionamento è mantenuto per confrontare la nuova batteria con il layer esistente; è distinto dallo stato che modula l'effetto, sempre pre-PR. La normalizzazione dello stato usa solo i controlli e non dipende dall'outcome scelto. Il requisito completo delle coppie e la disponibilità di cinque giornate per lo stato lento sono più restrittivi della copertura storica all'80% e della media su fino a cinque giornate disponibili: le variazioni di N vengono registrate.

`event_registry.csv` include ogni meeting del calendario, ogni radice e ogni fase, anche quando manca il contratto o la sorpresa. Distingue copertura dei prezzi, positività BV/RV per il log, disponibilità di ciascun indicatore e status macro. I registri di campione prodotti dalla stima aggiungono le esclusioni effettive per modello, outcome, indicatore e leave-top-K. Non si impone che moduli con requisiti diversi abbiano artificialmente lo stesso N.

## Indicatori e confronti di fase

La proxy primaria allineata è il rendimento logaritmico Schatz cambiato di segno; la coordinata azionaria è il rendimento netto fx nella medesima fase. Entrambe le coordinate devono chiudersi con l'outcome. Le unità sono deviazioni standard sui controlli PR/PC pooled, comuni alle due fasi e senza centratura. Non sono punti base di tasso e non sono uno shock strutturale esogeno.

La sensibilità Schatz–Bobl è la media a pesi uguali dei due rendimenti di prezzo cambiati di segno e divisi per le rispettive deviazioni standard sui controlli. OIS1Y e PC1 EA-EMPD restano due rami distinti, con la coordinata azionaria della fonte. Per PC sono esplicitamente **ex post**: cambiare la scadenza OIS non corregge il disallineamento temporale. Per ciascun ramo si stima sul suo campione PR/PC appaiato, e poi sul campione comune a tutti i rami.

La batteria replica il contrasto della superficie quadratica dello Step 24 e la geometria invariante dello Step 25 nel runner finale. Non chiama automaticamente le vecchie funzioni 24–25, che dipendono dai manifest e dai gate storici. La metrica geometrica è la covarianza pooled delle coordinate, contando una sola osservazione per meeting-fase; gli intervalli bootstrap sono condizionati a questa metrica. Le rotazioni a 0.1, 0.25, 0.5, 0.75, 0.9 sono un audit finito, non l'intero insieme identificato e non una prova di attribuzione MP/CBI.

Leave-top-K usa K=0,1,3,5 e ranking per energia totale, MP e CBI a livello meeting. Togliere un meeting elimina entrambe le fasi e tutti i suoi asset. La rotazione usa i meeting appaiati del campione dichiarato e viene ristimata nel campione ridotto; questa scelta va distinta dalla rotazione storica stimata sul calendario completo della fonte. Il controfattuale, stimato sui giorni non ECB, rimane invariato quando si eliminano soltanto meeting ECB. Ogni contrasto dichiarato ha un p wild; nessun p classico viene promosso al suo posto.

## Livello 1 e inferenza

Il ramo di media usa la sorpresa PR OIS1M/10, firmata e assoluta in specificazioni distinte, stato pre-PR, interazione sorpresa×stato, regime e indicatore asset. La risposta è il log BV anomalo; RV è sensibilità. Si testa l'interazione con wild cluster per meeting e correzione Holm della famiglia primaria. Le predizioni fuori campione escludono un intero anno dai meeting di training **e dai controlli usati dal primo stadio**. Tutta la centratura e la scala dello stato sono ristimate sui soli controlli di training. Non è una previsione in tempo reale: leave-year-out può usare anni successivi al fold di test.

Il ramo di sufficienza usa la media a pesi uguali di fx e gg, richiedendo entrambi gli asset. Confronta il partial R² del blocco di stato con l'incremento di due sole variabili storiche: lag-1 e media dei tre precedenti OIS1M PR. I lag si costruiscono sul calendario integrale della fonte prima delle esclusioni; un dato mancante non viene saltato. Il risultato riguarda questa storia osservata e questa risposta aggregata, non l'intero stato teorico né la proprietà quasi-Markov generale. T_e e P_e restano esplicitamente non disponibili, senza proxy inventate.

Il floor di potenza è una calibrazione condizionata al disegno, a livello meeting, lungo ciascuna delle due coordinate storiche residualizzate. Riporta anche size a R²=0 e usa il limite inferiore Wilson per dichiarare raggiunta potenza 0.80. Un mancato raggiungimento sulla griglia produce NaN; non estrapola una numerosità universale. L'upper bound percentile del partial R² è un diagnostico bootstrap, non un intervallo esatto. La regola finita richiede sia il bound sotto 0.02 sia potenza adeguata a quella scala. Una mancata reiezione non certifica sufficienza.

Il wild principale impone il null ristretto, usa segni Rademacher comuni a tutti gli asset e le fasi del meeting, studentizzazione CR1 e p-value con correzione plus-one, 999 repliche. I p-value sono **condizionati agli indicatori misurati e al controfattuale stimato**. Questa versione non integra l'incertezza dei regressori generati e del primo stadio in un bootstrap congiunto. Non va descritta come tale. Gli output mantengono questa limitazione nel manifest e nelle tabelle. Holm distingue famiglie primarie da sensibilità; la griglia di sensibilità non seleziona il modello primario.

## Rilasci USA

Il flag delle 08:30 `America/New_York` considera ogni giorno feriale, gestisce DST e include conservativamente coincidenze sui bordi. È una possibile esposizione, non un calendario verificato di pubblicazioni. La sensibilità elimina il meeting appaiato se una delle sue fasi è esposta e ristima il layer normale dopo lo stesso filtro sui controlli. Il ramo scalare PR applica invece il filtro alle sole coincidenze PR, con la stessa esclusione nei propri controlli. La sola presenza di effetti per giorno della settimana non dimostra che la sorpresa macro sia assorbita.

Si può fornire `Raw/Certification/us_releases.csv` nel data root, con colonne `release_id,timestamp_utc,source_url` e timestamp UTC espliciti. Il build ne incorpora hash e flag dei rilasci. Senza il file, lo status è `candidate_screen_only`. La sensibilità conservativa resta calcolabile, anche se può fallire il gate di 30 meeting; il fallimento va riportato, non aggirato scegliendo le esclusioni dopo la stima.

## Esecuzione e conservazione

Il runner Python permette di verificare il disegno sui dati disponibili senza una licenza MATLAB; le correzioni agli estrattori e allo shrinkage restano anche nel codice MATLAB. Requisiti: Python 3.10+ e `requirements-final-analysis.txt` (versioni effettive salvate nel manifest).

```bash
python3 -m pip install -r requirements-final-analysis.txt
./Run_final_analysis.sh freeze --data-root /path/to/Econometrics_data \
  --build /path/to/Econometrics_data/Raw/Certification/final_analysis_v1
./Run_final_analysis.sh estimate --data-root /path/to/Econometrics_data \
  --build /path/to/Econometrics_data/Raw/Certification/final_analysis_v1 \
  --output /path/to/Econometrics_data/Output/final_analysis_v1
```

Un percorso già esistente viene rifiutato: per una revisione usare una nuova directory. La stima verifica gli hash del codice eseguibile, della specifica, dei dati sorgente e delle tabelle congelate. Modificare il codice dopo il congelamento richiede un nuovo build. `--smoke` su `estimate` usa 19 repliche e una griglia ridotta: ogni output è marcato `complete_smoke_not_for_inference` e non sostiene conclusioni econometriche.

I nuovi output non sovrascrivono quelli storici. `Run_pipeline` rimane la pipeline storica per gli esercizi precedenti; non è l'entry point della stima finale. `Output/paper_tables` di aprile va trattato come **superseded** rispetto alle finestre canoniche: il runner non ne importa alcuna tabella e non ne cancella l'archivio.

Con cinque rendimenti PR lo Step 16 si ferma al gate BNS storico, che richiede una mediana di almeno sei. Questa soglia rimane invariata. Lo Step 17 registra il ramo BV come `blocked_bns_gate` e stima soltanto il diagnostico RV dal pannello di stato, senza usare eventuali file BNS residui. Il nuovo report di fattibilità vincola tramite hash barre, stato e, se prodotto, pannello BNS. I vecchi output BNS e quasi-Markov vengono archiviati prima di una nuova esecuzione. Questo arresto non blocca il calcolo della proxy bipower nella batteria finale Python.

Per il rerun ausiliario MATLAB:

```matlab
setenv('ECONOMETRICS_DATA_ROOT', '/path/to/Econometrics_data');
setenv('FINAL_ANALYSIS_BUILD', '/path/to/Econometrics_data/Raw/Certification/final_analysis_v1');
Run_final_matlab_checks
```

Il driver verifica gli input congelati, usa `preferred_contracts.csv` con selezione pre-PR, archivia le directory storiche `analysis` ed `event_windows`, ricostruisce le finestre e ristima anche lo shrinkage. La 1-SE sceglie la penalizzazione più forte nella banda; interazioni da variabili grezze, scaling, centratura e massimo lambda del fold evitano l'uso del test fold nel training. Le statistiche post-selezione sono etichettate descrittive. La penalizzazione sparse-group esistente non impone strong heredity.

Test riproducibili:

```bash
python3 -m unittest discover -s tests -v
```

In MATLAB: `Final_window_self_test`. Disponibilità e risultati delle verifiche effettuate in questa modifica sono riportati in `FINAL_ANALYSIS_VALIDATION.md`.
