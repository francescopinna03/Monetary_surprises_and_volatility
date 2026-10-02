# Evidenza automatizzata: calendario BCE e semantica delle barre

Due voci restavano aperte riga per riga: quali riunioni del 2000-2012 ebbero una
conferenza stampa, e se l'etichetta di una barra a cinque minuti sia l'inizio o
la fine del suo intervallo. Entrambe si automatizzano quasi del tutto. Nessuna
delle due si chiude senza una firma umana, e questo documento dice esattamente
dove passa il confine.

## Calendario BCE

La BCE pubblica due indici che sono i discriminanti che servono. L'indice delle
decisioni di politica monetaria elenca per anno ogni decisione del Consiglio
direttivo; l'archivio delle dichiarazioni introduttive dice, data per data, se
una conferenza stampa si e' tenuta.

Questo e' il punto sulle seconde riunioni del mese nel 2000-2001: il Consiglio
si riuniva due volte al mese, ma la conferenza seguiva solo la riunione di
politica monetaria. Non esiste una regola di calendario che lo risolva. Nel 2000
l'indice elenca 25 date di decisione e solo 13 dichiarazioni introduttive; nel
2001 la riunione di politica monetaria di agosto e' quella del 30, non quella
del 2. La presenza o assenza della dichiarazione per quella data e' la prova.

```bash
bash Run_confirmation.sh calendar-candidates \
  --data-root "$HOME/Desktop/Monetary_surprises_FULL_rqjB5J/Econometrics_data" \
  --output /percorso/uscita/ecb_calendar
```

Lo script scarica gli indici annuali 2000-2012 da
`/press/govcdec/mopo/<anno>/html/index_include.en.html` e
`/press/press_conference/monetary-policy-statement/<anno>/html/index_include.en.html`,
risolve ogni comunicato elencato, verifica che la data pubblicata nella pagina
(`article:published_time`, con la data stampata come riscontro) combaci con
quella dell'indice, e archivia ogni pagina letta con il suo SHA-256. Calcola
`event_datetime_utc` da 13:45 e 14:30 Europe/Berlin con fuso IANA, mai con un
offset fisso. Infine riconcilia l'elenco BCE con le date di EA-EMPD.

### Cosa lo script non fa

Scrive `verification_status=candidate`, mai `verified`.

**L'assenza di una pagina non e' prova dell'assenza dell'evento.** In venticinque
anni il sito BCE ha cambiato struttura piu' volte e gli URL del 2000-2001 non
hanno lo schema di oggi. Se un comunicato non si risolve, lo script non produce
alcuna riga per quella data: la manda in coda di revisione come
`unresolved_evidence`. Marcare `actual_phase_present=false` su un 404 avrebbe
eliminato un'osservazione valida dal campione di conferma, in silenzio e senza
che alcun test se ne accorgesse. L'errore opposto, includere una conferenza mai
avvenuta, e' peggio.

Una data assente dall'indice annuale delle dichiarazioni e' invece un'assenza
dichiarata dalla fonte, non un URL rotto: lo script la propone come
`statement_absent_from_annual_index`, e quella proposta resta promuovibile solo
riga per riga. Una promozione in blocco che incontri una proposta di assenza non
revisionata si ferma con `UNREVIEWED_ABSENCE`.

Non deduce nulla dai picchi di volume, per lo stesso motivo per cui il resto
della catena non lo fa: l'unica cosa che rende credibile un campione di conferma
e' poter dire come si sa cio' che si afferma.

### Cosa resta assunto

Le pagine BCE portano la **data** di un evento, non l'**ora**. Gli orari 13:45 e
14:30 sono lo schedule regolare storico, non evidenza di pagina: la colonna
`timestamp_basis` lo dichiara riga per riga e il report di prontezza tiene
`external_window_timing` bloccante esattamente per questo. Le due deroghe note,
17 settembre 2001 e 8 ottobre 2008, non ricevono alcun timestamp: chi revisiona
deve fornirlo in `reviewer_event_datetime_utc`, altrimenti la promozione si
ferma con `MISSING_TIMESTAMP`.

### Uscite

| File | Contenuto |
|---|---|
| `ecb_calendar_candidates.csv` | Una riga per data e fase, con URL, stato HTTP, titolo, data estratta e frammento di testo su cui lo script ha deciso |
| `ecb_pages.csv` | Ogni pagina risolta, con il suo hash e la classificazione del titolo |
| `ecb_calendar_reconciliation.csv` | Elenco BCE contro EA-EMPD, con il tipo di discrepanza |
| `ecb_calendar_review_queue.csv` | Le sole righe dove una decisione umana cambia il campione |
| `pages/` | Archivio delle pagine lette; non entra nel repository |

### Revisione

La coda apre cinque strati, e nient'altro:

- `timing_exception` — 17 settembre 2001 e 8 ottobre 2008;
- `anomalous_weekday` — ogni data che non cade di giovedi', una per una;
- `multiple_meetings_in_month_2000_2001` — i mesi del biennio con piu' di una
  riunione, dove la decisione presente/assente cambia il campione;
- `proposed_absence` — ogni conferenza proposta come assente;
- `reconciliation_discrepancy` e `unresolved_evidence` — i disaccordi fra le due
  liste e le pagine che non si sono risolte;

piu' un campione casuale di venti righe ordinarie, con seme fissato, per
validare l'estrattore. Se quel campione e' pulito, il resto si promuove in
blocco con una regola scritta:

```bash
bash Run_confirmation.sh calendar-promote \
  --candidates /percorso/uscita/ecb_calendar \
  --reviewed-queue /percorso/coda_revisionata.csv \
  --output .../Raw/Certification/ecb_calendar_verified_v2.csv \
  --reviewer "Francesco Pinna" \
  --rule "Righe ordinarie promosse in blocco: comunicato e dichiarazione si risolvono sull'archivio BCE e la data pubblicata combacia con l'indice annuale. Ogni riga aperta e' stata revisionata singolarmente."
```

La promozione rifiuta una coda con anche una sola riga senza
`reviewer_decision`, una riga senza revisore, una decisione diversa da
`true`/`false`/`exclude`, una promozione senza nome e senza regola, e ogni
assenza o evidenza irrisolta non revisionata singolarmente. Regola, revisore e
hash della coda finiscono in `ecb_calendar_verified_v2_promotion.json`.

Cinquanta righe aperte davvero invece di trecentosessantadue, e una regola
documentata per il resto.

## Semantica delle barre

Il test empirico ovvio - quale barra contiene il movimento dell'annuncio - e'
circolare: usa l'annuncio per stabilire l'etichetta e poi l'etichetta per
misurare l'annuncio.

L'alternativa e' il confine di sessione, che con gli annunci non ha nulla a che
fare. Si confrontano la prima e l'ultima barra osservata con l'orario di
negoziazione Eurex pubblicato per quell'epoca. Se la sessione chiude alle 22:00
e l'ultima barra e' etichettata 21:55, l'etichetta e' inizio intervallo; se
l'ultima e' 22:00 e la prima e' una barra dopo l'apertura, e' fine intervallo.
Un giorno che non corrisponde a nessuno dei due schemi resta inconcludente e non
vota.

L'unica cosa umana e' procurarsi lo schedule storico: una volta per epoca, non
per file.

```bash
bash Run_confirmation.sh trading-hours-template --output config/eurex_trading_hours.csv
# compilare a mano: root_code, period_start_date, period_end_date,
# session_open_wall, session_close_wall, timezone, source_url, reviewer, notes

bash Run_confirmation.sh bar-label-evidence \
  --primary-files /percorso/confirmation_quality_RUN/quality/primary_files.csv \
  --schedule config/eurex_trading_hours.csv \
  --output /percorso/uscita/bar_label
```

Non esiste uno schedule di ripiego. Il caricatore rifiuta un file assente
(`EUREX_SCHEDULE_MISSING`), il template vuoto (`EUREX_SCHEDULE_EMPTY`), un'epoca
senza URL di fonte o senza revisore (`EUREX_SCHEDULE_UNSOURCED`), epoche
sovrapposte (`EUREX_SCHEDULE_OVERLAP`) e piu' fusi orari nello stesso file. Un
confine di sessione indovinato sceglierebbe in silenzio una convenzione di
barra.

Le date nello schedule si scrivono in formato ISO `YYYY-MM-DD`; `root_code`
accetta `all` per un'epoca valida su tutte le radici.

La decisione si aggrega sulla cella (radice, periodo triennale) che l'audit di
qualita' usa gia'. Una cella si chiude solo se tutti i giorni conclusivi
concordano e sono almeno `--minimum-days`, venti per default; se i due schemi
ricevono voti nella stessa cella il conflitto e' registrato e la cella resta
aperta.

```bash
bash Run_confirmation.sh bar-label-promote \
  --evidence /percorso/uscita/bar_label \
  --output .../Raw/Certification/bar_label_evidence_v2.csv \
  --reviewer "Francesco Pinna" \
  --rule "Celle i cui confini di sessione conclusivi concordano su una sola convenzione, su almeno venti giorni dello schedule Eurex pubblicato per l'epoca."
```

L'uscita e' il file che `quality_audit` legge: una riga per cella, con la
convenzione, l'URL dello schedule come fonte, il revisore e l'hash del file
rappresentativo che lega l'evidenza all'inventario.

Un test dimostra la non circolarita': cancellando ogni barra fra le 13:00 e le
15:00 - cioe' tutta la finestra dell'annuncio - la decisione e il conteggio dei
giorni a favore non cambiano.
