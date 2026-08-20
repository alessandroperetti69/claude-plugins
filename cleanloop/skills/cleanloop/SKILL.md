---
name: cleanloop
description: Lavora su task lunghi mantenendo il contesto pulito (sotto il 25% della finestra). Usa questa skill quando l'utente dice "cleanloop", "contesto pulito", "checkpoint", "salva lo stato e continua", "riprendi da PROGRESS.md", vuole avviare un loop autonomo su un task, o quando l'hook cleanloop segnala che il contesto ha superato la soglia. Definisce il protocollo di checkpoint (PROGRESS.md + CLAUDE.md), come riprendere dopo /clear e come lanciare il loop a sessioni fresche.
---

# cleanloop

Obiettivo: il contesto resta piccolo, lo **stato vive nei file** (`PROGRESS.md` per l'avanzamento, `CLAUDE.md` per i fatti durevoli), e il task avanza per **sotto-task chiusi e verificati**. Il plugin ha tre parti: questa skill (protocollo), gli hook (misurano il contesto e ti avvisano), il runner `scripts/cleanloop.sh` (loop a sessioni fresche).

## 1. Capire in che situazione sei

| Situazione | Cosa fare |
|---|---|
| L'utente vuole avviare un task lungo/autonomo | → §2 Setup, poi proponi il loop (§5) |
| L'hook ha scritto `[cleanloop] CONTESTO AL N%` | → §3 Checkpoint, subito |
| Sessione appena ripulita (`/clear`, `/compact`) e `PROGRESS.md` è stato iniettato | → §4 Ripresa |
| L'utente dice "/cleanloop" senza altro | → mostra stato (`bash <plugin>/scripts/cleanloop.sh status`) e chiedi cosa vuole: setup, checkpoint manuale o run |

Il percorso del plugin è la cartella che contiene questa skill, due livelli sopra (`skills/cleanloop/SKILL.md` → radice). Se non lo conosci: `find ~/.claude /path -name cleanloop.sh -path '*cleanloop/scripts*' 2>/dev/null | head -1`.

## 2. Setup di un progetto (una volta)

1. `bash <plugin>/scripts/cleanloop.sh init` nella radice del progetto → crea `TASK.md`, `PROGRESS.md`, `.cleanloop/{config,enabled,state,logs}`. Da terminale, senza `--task`/`--brief`, apre un wizard (obiettivo, task uno per riga, vincoli). Da questo momento gli hook sono attivi in questa cartella.
   - **Modalità brief**: invece di strutturare i task a mano, si può dare in pasto un prompt libero o un documento e lasciare che sia la prima iterazione a organizzarsi la coda. Si attiva con `--brief PATH` (o `--brief -` per stdin), oppure automaticamente se `BRIEF.md` esiste già in radice, oppure se arriva testo da stdin non interattivo (es. `pbpaste | cleanloop.sh init`) — utile per evitare l'incollaggio riga-per-riga nel wizard, che si rompe con testo multi-riga. In questo caso `TASK.md` ha un solo `T1` che chiede alla prima iterazione di leggere `BRIEF.md`, derivare Obiettivo + coda reale e riscrivere `TASK.md`, **senza** iniziare lavoro applicativo in quel turno. Consigliato: `cleanloop.sh once` per rivedere il piano generato prima di lanciare `run`.
2. `TASK.md`: la sezione **`## Task`** è la **coda** dell'utente (`- [ ] T1: …`), che può crescere in ogni momento con `cleanloop add "…"` (anche mentre il loop gira). Aiuta l'utente a rendere verificabile la **Definizione di fatto** e a esplicitare vincoli e cosa non toccare.
3. `PROGRESS.md`: il **Piano** rispecchia la coda (stessi ID `Tn`), eventualmente spezzando un task in sotto-task; a ogni ripresa confronta coda e Piano e aggiungi le voci nuove. Obiettivo in 1 riga, primo handoff.
4. Facoltativo: soglie e altri parametri in `.cleanloop/config` (`CLEANLOOP_THRESHOLD`, default 25; `CLEANLOOP_HARD`, default 40; `CLEANLOOP_EFFORT`, `CLEANLOOP_USE_SUBAGENTS`, default 0 — se 1 l'iterazione valuta il parallelismo con l'Agent tool sui task indipendenti; ecc.) — configurabili da CLI senza editare il file: `cleanloop init --threshold N --hard N ...` al setup, oppure `cleanloop config CHIAVE=VALORE` dopo (anche a progetto già inizializzato). Il wizard interattivo (`cleanloop init` senza flag) chiede questi stessi parametri in sequenza dopo obiettivo/task/vincoli, invio = mantiene il default mostrato.

## 3. Protocollo di checkpoint (quando l'hook lo chiede, o ogni sotto-task chiuso)

Esegui **in questo ordine**, senza iniziare nulla di nuovo:

1. **Stato consistente**: nessun file a metà; se esiste un test/build veloce, eseguilo.
2. **`PROGRESS.md`** — riscrivi (non accumulare) le sezioni:
   - `STATUS:` `IN_PROGRESS` | `DONE` | `BLOCKED` — `ITERATION:` +1
   - **Fatto** (bullet sintetici, con il "come verificato")
   - **In corso** (se qualcosa è a metà: cosa e dove esattamente)
   - **Prossimo passo (handoff)**: file, comando, cosa verificare — deve permettere a un agente con contesto vuoto di ripartire senza esplorare
   - **Piano** spuntato — **Decisioni** (con motivo, 1 riga) — **Trappole/note** (cose che fanno perdere tempo)
   - Limite ~40 righe: se cresce, comprimi "Fatto".
3. **`CLAUDE.md`** — solo fatti *durevoli* del progetto scoperti ora (comando di test, convenzione, vincolo architetturale, gotcha dell'ambiente): 1-3 righe, nella sezione giusta. **Mai** log di sessione, mai "oggi ho fatto".
4. **Poi**:
   - in **modalità loop** (`CLEANLOOP_ACTIVE=1`, sessione `-p`): termina il turno con 2-4 righe di riepilogo. Il runner riparte con contesto vuoto.
   - in **modalità interattiva**: di' all'utente, testualmente: *"Checkpoint salvato in PROGRESS.md. Esegui `/clear` e poi `/cleanloop` per riprendere con contesto pulito."* Tu non puoi eseguire `/clear`: non provarci, non simularlo.

Se `STATUS: DONE`: verifica prima che ogni voce della "Definizione di fatto" in `TASK.md` sia soddisfatta e verificata. Se `BLOCKED`: scrivi motivo e cosa serve dall'umano.

## 4. Ripresa dopo /clear, /compact o in una nuova iterazione

- **Non ricostruire la storia**, non ri-esplorare il repo per "farti un'idea": `PROGRESS.md` + `CLAUDE.md` sono la verità. Leggi solo i file citati nell'handoff.
- Riparti dal **Prossimo passo**. Se l'handoff è ambiguo, la prima azione è chiarirlo (leggendo il minimo indispensabile) e riscriverlo.
- Un sotto-task per volta; chiudi e verifica; checkpoint; avanti.

## 5. Il loop a sessioni fresche (modalità consigliata per task lunghi)

```bash
bash <plugin>/scripts/cleanloop.sh run          # fino a STATUS: DONE/BLOCKED, max CLEANLOOP_MAX_ITER (20)
bash <plugin>/scripts/cleanloop.sh run -n 5     # al massimo 5 iterazioni
bash <plugin>/scripts/cleanloop.sh once         # una sola iterazione
bash <plugin>/scripts/cleanloop.sh status       # STATUS, iterazione, ultimo % contesto, log
```

Come funziona: ogni iterazione è un `claude -p` nuovo (contesto vuoto) con `--plugin-dir` (hook attivi) e un system prompt di iterazione; `SessionStart` inietta `TASK.md` + `PROGRESS.md`; `PostToolUse` misura i token dal transcript e alla soglia chiede il checkpoint; `Stop` impedisce di uscire senza aver aggiornato `PROGRESS.md`. Il runner si ferma su `DONE`, `BLOCKED`, max iterazioni, o **stallo** (N iterazioni senza modifiche a `PROGRESS.md`). Log per iterazione in `.cleanloop/logs/`.

Se lo lanci tu dalla sessione interattiva: usalo con `run_in_background` e spiega all'utente che le iterazioni sono processi separati (non vedrà il lavoro nel contesto corrente ma in `PROGRESS.md` e nei log). Preferibile: suggerire all'utente di lanciarlo da terminale.

Permessi: in `-p` nessuno risponde ai prompt di permesso. Default `--permission-mode auto`; `bypassPermissions` solo in sandbox (config `CLEANLOOP_PERMISSION_MODE`).

## 6. Anti-pattern da evitare

- Fare checkpoint "narrativi" (cosa hai pensato) invece che operativi (dove riprendere).
- Mettere in `CLAUDE.md` lo stato di avanzamento: va in `PROGRESS.md`.
- Ignorare l'avviso di soglia "perché manca poco": il contesto grande degrada la qualità *prima* di finire.
- Iterazioni che aprono tre fronti: una iterazione, un sotto-task, una verifica.
- Segnare `DONE` senza aver eseguito la verifica scritta in `TASK.md`.
