import { useEffect, useState } from "react";
import {
  closestCenter,
  DndContext,
  KeyboardSensor,
  MouseSensor,
  TouchSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  arrayMove,
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import {
  ArrowLeft,
  BarChart3,
  ChevronDown,
  ChevronUp,
  GripVertical,
  Maximize2,
  Pencil,
  Plus,
  Save,
  SlidersHorizontal,
  Trash2,
  Vote,
  X,
} from "lucide-react";
import "./App.css";
import {
  createCategory,
  deleteCategory,
  fetchCategoryRankings,
  fetchSetup,
  submitRankedBallot,
  updateCategory,
} from "./lib/api";
import { hasSupabaseConfig } from "./lib/supabase";
import { getVoterKey } from "./lib/voter";

const blankDraft = { description: "", heroIds: [], name: "" };

function App() {
  const poll = usePoll();
  return (
    <main className="app-shell">
      <HeroHeader />
      <SetupNotice />
      <PollArea poll={poll} />
    </main>
  );
}

function usePoll() {
  const [state, setState] = useState(makeInitialState);
  useEffect(() => {
    void loadSetup(setState);
  }, []);
  return buildActions(state, setState);
}

function buildActions(state, setState) {
  return {
    ...state, cancelVote: () => showCategoryStart(setState),
    closeDrawer: () => setDrawerOpen(false, setState), closeResults: () => closeResults(setState),
    createCategory: (draft) => saveNewCategory(draft, setState), deleteCategory: (id) => removeCategory(id, setState),
    moveHero: (heroId, offset) => moveRankedHero(heroId, offset, setState), openDrawer: () => setDrawerOpen(true, setState),
    openResults: (category) => loadResults(category, setState), refresh: () => loadSetup(setState),
    reorderHero: (activeId, overId) => reorderRankedHero(activeId, overId, setState),
    showResultModal: () => setResultView("modal", setState), showResultPage: () => setResultView("page", setState),
    startCategory: (category) => startCategoryRanking(category, state.heroes, setState),
    submitRanking: () => saveRanking(state, setState), updateCategory: (id, draft) => saveCategoryEdit(id, draft, setState),
  };
}

function makeInitialState() {
  return {
    activeCategory: null, categories: [], categoryBusy: false, completedCategory: null,
    drawerOpen: false, error: "", heroes: [], rankingIds: [], resultCategory: null,
    resultError: "", resultRankings: [], resultStatus: "idle", resultView: "modal",
    status: hasSupabaseConfig ? "loading" : "setup",
    submitBusy: false,
  };
}

async function loadSetup(setState, status = "idle") {
  if (!hasSupabaseConfig) return;
  setState((data) => ({ ...data, error: "", status: "loading" }));
  try {
    setSetupLoaded(await fetchSetup(), status, setState);
  } catch (error) {
    setLoadError(error, setState);
  }
}

function setSetupLoaded(setup, status, setState) {
  setState((data) => ({
    ...data,
    ...setup,
    activeCategory: null,
    categoryBusy: false,
    rankingIds: [],
    status,
  }));
}

function startCategoryRanking(category, heroes, setState) {
  const rankingIds = shuffledHeroIds(category, heroes);
  if (rankingIds.length < 2)
    return setInlineError("Category needs at least two heroes.", setState);
  setState((data) => ({
    ...data,
    activeCategory: category,
    completedCategory: null,
    error: "",
    rankingIds,
    status: "ranking",
  }));
}

async function saveRanking(state, setState) {
  if (!state.activeCategory || state.rankingIds.length < 2) return;
  setState((data) => ({ ...data, error: "", submitBusy: true }));
  try {
    await submitRankedBallot(
      state.activeCategory.id,
      state.rankingIds,
      getVoterKey(),
    );
    setRankingDone(state.activeCategory, setState);
  } catch (error) {
    setActionError(error, setState);
  }
}

function setRankingDone(category, setState) {
  setState((data) => ({
    ...data,
    activeCategory: null,
    completedCategory: category,
    rankingIds: [],
    status: "done",
    submitBusy: false,
  }));
}

async function loadResults(category, setState) {
  setState((data) => ({ ...data, resultCategory: category, resultError: "", resultRankings: [], resultStatus: "loading", resultView: "modal" }));
  try {
    setResultsLoaded(category, await fetchCategoryRankings(category.id), setState);
  } catch (error) {
    setResultsError(error, setState);
  }
}

function setResultsLoaded(category, rankings, setState) {
  setState((data) => ({
    ...data,
    resultCategory: category,
    resultRankings: rankings,
    resultStatus: "ready",
  }));
}

async function saveNewCategory(draft, setState) {
  setBusy(setState, true);
  try {
    await createCategory(...cleanDraftArgs(draft));
    await loadSetup(setState);
    return true;
  } catch (error) {
    setActionError(error, setState);
    return false;
  }
}

async function saveCategoryEdit(id, draft, setState) {
  setBusy(setState, true);
  try {
    await updateCategory(id, ...cleanDraftArgs(draft));
    await loadSetup(setState);
    return true;
  } catch (error) {
    setActionError(error, setState);
    return false;
  }
}

async function removeCategory(id, setState) {
  setBusy(setState, true);
  try {
    await deleteCategory(id);
    await loadSetup(setState);
  } catch (error) {
    setActionError(error, setState);
  }
}

function HeroHeader() {
  return (
    <header className="hero-header">
      <h1>Marvel Rivals Hero Vote</h1>
    </header>
  );
}

function SetupNotice() {
  if (hasSupabaseConfig) return null;
  return (
    <section className="notice">
      Add Supabase values to <code>.env</code>, then run the SQL migrations.
    </section>
  );
}

function PollArea({ poll }) {
  if (poll.status === "setup") return <EmptyState />;
  if (poll.resultCategory && poll.resultView === "page")
    return <ResultsPage poll={poll} />;
  return (
    <>
      <ManageButton poll={poll} />
      <section className="poll-layout">
        <VotingStage poll={poll} />
      </section>
      {poll.drawerOpen && <CategoryDrawer poll={poll} />}
      {poll.resultCategory && poll.resultView === "modal" && <ResultsModal poll={poll} />}
    </>
  );
}

function ManageButton({ poll }) {
  return (
    <button className="drawer-fab" onClick={poll.openDrawer} type="button">
      <SlidersHorizontal size={18} />
      <span>Manage Categories</span>
    </button>
  );
}

function VotingStage({ poll }) {
  if (poll.status === "loading")
    return <StatusMessage text="Loading voting flow..." />;
  if (poll.status === "error") return <ErrorMessage poll={poll} />;
  if (poll.status === "done") return <DoneStage poll={poll} />;
  if (poll.status === "ranking") return <RankingStage poll={poll} />;
  return <StartStage poll={poll} />;
}

function StartStage({ poll }) {
  return (
    <section className="start-panel">
      <p className="eyebrow">Category select</p>
      <h2>Choose Category</h2>
      <CategoryPicker poll={poll} />
    </section>
  );
}

function CategoryPicker({ poll }) {
  if (!poll.categories.length)
    return <p className="muted">Add at least one category before voting.</p>;
  return (
    <div className="session-categories" aria-label="Voting categories">
      {poll.categories.map((item) => (
        <CategoryChoice item={item} key={item.id} poll={poll} />
      ))}
    </div>
  );
}

function CategoryChoice({ item, poll }) {
  const disabled = item.heroIds.length < 2;
  return (
    <button
      disabled={disabled}
      onClick={() => poll.startCategory(item)}
      type="button"
    >
      <Vote size={18} />
      <span>{item.name}</span>
      <strong>{item.heroIds.length} heroes</strong>
    </button>
  );
}

function RankingStage({ poll }) {
  const heroes = rankedHeroes(poll);
  return (
    <section className="ranking-panel">
      <RankingHeader category={poll.activeCategory} total={heroes.length} />
      <RankingList heroes={heroes} poll={poll} />
      <RankingActions poll={poll} />
      <InlineError error={poll.error} />
    </section>
  );
}

function RankingHeader({ category, total }) {
  return (
    <div className="ranking-header">
      <p className="eyebrow">Category</p>
      <h2>{category.name}</h2>
      <p>{category.description || "Eligible hero roster for this category."}</p>
      <div className="progress-strip">
        <span>{total} heroes</span>
      </div>
    </div>
  );
}

function RankingList({ heroes, poll }) {
  const sensors = useRankingSensors();
  return (
    <DndContext collisionDetection={closestCenter} onDragEnd={(event) => handleSortEnd(event, poll)} sensors={sensors}>
      <SortableContext items={heroes.map((hero) => hero.id)} strategy={verticalListSortingStrategy}>
        <div className="ranking-list">{heroes.map((hero, index) => <RankingItem hero={hero} index={index} key={hero.id} poll={poll} total={heroes.length} />)}</div>
      </SortableContext>
    </DndContext>
  );
}

function RankingItem({ hero, index, poll, total }) {
  const sortable = useSortable({ id: hero.id });
  const dragging = sortable.isDragging ? " dragging" : "";
  return (
    <article className={`ranking-item ${roleClass(hero.role)}${dragging}`} ref={sortable.setNodeRef} style={sortableStyle(sortable)}>
      <strong className="rank-number">{index + 1}</strong>
      <DragHandle hero={hero} sortable={sortable} /><HeroPortrait hero={hero} /><HeroCopy hero={hero} />
      <RankControls hero={hero} index={index} poll={poll} total={total} />
    </article>
  );
}

function DragHandle({ hero, sortable }) {
  return <button aria-label={`Drag ${hero.name}`} className="drag-handle" type="button" {...sortable.attributes} {...sortable.listeners}><GripVertical size={22} /></button>;
}

function HeroCopy({ hero }) {
  return <div className="hero-copy"><p>{hero.role}</p><h2>{hero.name}</h2></div>;
}

function useRankingSensors() {
  return useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 4 } }),
    useSensor(TouchSensor, {
      activationConstraint: { delay: 260, tolerance: 8 },
    }),
    useSensor(KeyboardSensor, {
      coordinateGetter: sortableKeyboardCoordinates,
    }),
  );
}

function handleSortEnd(event, poll) {
  if (!event.over || event.active.id === event.over.id) return;
  poll.reorderHero(event.active.id, event.over.id);
}

function sortableStyle(sortable) {
  return {
    transform: CSS.Transform.toString(sortable.transform),
    transition: sortable.transition,
  };
}

function RankControls({ hero, index, poll, total }) {
  return (
    <div className="rank-controls">
      <MoveButton disabled={index === 0} hero={hero} icon={<ChevronUp size={18} />} label="up" offset={-1} poll={poll} />
      <MoveButton disabled={index === total - 1} hero={hero} icon={<ChevronDown size={18} />} label="down" offset={1} poll={poll} />
    </div>
  );
}

function MoveButton({ disabled, hero, icon, label, offset, poll }) {
  return <button aria-label={`Move ${hero.name} ${label}`} disabled={disabled} onClick={() => poll.moveHero(hero.id, offset)} type="button">{icon}</button>;
}

function RankingActions({ poll }) {
  return (
    <div className="ranking-actions">
      <RankingAction className="start-button" disabled={poll.submitBusy} icon={<Save size={18} />} label="Submit Ranking" onClick={poll.submitRanking} />
      <RankingAction className="secondary-button" disabled={poll.submitBusy} icon={<ArrowLeft size={18} />} label="Back" onClick={poll.cancelVote} />
    </div>
  );
}

function RankingAction({ className, disabled, icon, label, onClick }) {
  return <button className={className} disabled={disabled} onClick={onClick} type="button">{icon}<span>{label}</span></button>;
}

function CategoryDrawer({ poll }) {
  const editor = useCategoryEditor(poll);
  return (
    <div className="drawer-layer">
      <button className="drawer-backdrop" aria-label="Close category manager" onClick={poll.closeDrawer} type="button" />
      <aside className="category-drawer"><DrawerHeader poll={poll} /><CategoryForm editor={editor} poll={poll} /><CategoryList editor={editor} poll={poll} /></aside>
    </div>
  );
}

function useCategoryEditor(poll) {
  const [draft, setDraft] = useState(blankDraft);
  const [editingId, setEditingId] = useState("");
  useEffect(() => {
    setDraft((data) => initialHeroDraft(data, editingId, poll.heroes));
  }, [poll.heroes, editingId]);
  return useEditorApi(draft, editingId, poll, setDraft, setEditingId);
}

function useEditorApi(draft, editingId, poll, setDraft, setEditingId) {
  return {
    cancel: () => cancelCategoryEdit(setDraft, setEditingId), draft,
    edit: (category) => startCategoryEdit(category, setDraft, setEditingId), editingId,
    setDescription: (description) => setDraft((data) => ({ ...data, description })),
    setHeroIds: (heroIds) => setDraft((data) => ({ ...data, heroIds })),
    setName: (name) => setDraft((data) => ({ ...data, name })),
    toggleHero: (heroId) => setDraft((data) => ({ ...data, heroIds: toggleId(data.heroIds, heroId) })),
    submit: (event) => submitCategoryForm(event, poll, draft, editingId, setDraft, setEditingId),
  };
}

function DrawerHeader({ poll }) {
  return (
    <div className="drawer-header">
      <div><p className="eyebrow">Manage</p><h2>Categories</h2></div>
      <button aria-label="Close category manager" onClick={poll.closeDrawer} type="button"><X size={20} /></button>
    </div>
  );
}

function CategoryForm({ editor, poll }) {
  return (
    <form className="category-form" onSubmit={editor.submit}>
      <CategoryTextFields editor={editor} />
      <HeroEligibility editor={editor} heroes={poll.heroes} />
      <CategoryFormActions editor={editor} poll={poll} />
    </form>
  );
}

function CategoryTextFields({ editor }) {
  return <><input onChange={(event) => editor.setName(event.target.value)} placeholder="Category name" required value={editor.draft.name} /><textarea onChange={(event) => editor.setDescription(event.target.value)} placeholder="Description" value={editor.draft.description} /></>;
}

function CategoryFormActions({ editor, poll }) {
  return <div className="form-actions"><button disabled={!canSaveCategory(editor, poll)}>{editor.editingId ? <Save size={17} /> : <Plus size={17} />}<span>{editor.editingId ? "Save" : "Add"}</span></button>{editor.editingId && <button onClick={editor.cancel} type="button"><X size={17} /><span>Cancel</span></button>}</div>;
}

function HeroEligibility({ editor, heroes }) {
  return (
    <div className="hero-eligibility">
      <PresetButtons editor={editor} heroes={heroes} />
      <HeroIconGrid editor={editor} heroes={heroes} />
    </div>
  );
}

function PresetButtons({ editor, heroes }) {
  return (
    <div className="preset-buttons">
      {presetOptions(heroes).map((preset) => (
        <PresetButton editor={editor} key={preset.name} preset={preset} />
      ))}
    </div>
  );
}

function PresetButton({ editor, preset }) {
  const active = presetActive(editor.draft.heroIds, preset);
  return (
    <button
      className={active ? "active" : ""}
      onClick={() => editor.setHeroIds(preset.heroIds)}
      type="button"
    >
      {preset.name}
    </button>
  );
}

function HeroIconGrid({ editor, heroes }) {
  return (
    <div className="hero-icon-grid">
      {heroes.map((hero) => (
        <HeroIconButton editor={editor} hero={hero} key={hero.id} />
      ))}
    </div>
  );
}

function HeroIconButton({ editor, hero }) {
  const selected = editor.draft.heroIds.includes(hero.id);
  return (
    <button
      className={selected ? "selected" : ""}
      onClick={() => editor.toggleHero(hero.id)}
      title={hero.name}
      type="button"
    >
      <HeroPortrait hero={hero} />
    </button>
  );
}

function CategoryList({ editor, poll }) {
  if (!poll.categories.length)
    return <p className="muted">Add at least one category before voting.</p>;
  return (
    <div className="category-list">
      {poll.categories.map((item) => (
        <CategoryItem editor={editor} item={item} key={item.id} poll={poll} />
      ))}
    </div>
  );
}

function CategoryItem({ editor, item, poll }) {
  return (
    <article className="category-item">
      <div className="category-name">{item.name}</div>
      <p className="muted">{item.heroIds.length} heroes</p>
      <CategoryActions editor={editor} item={item} poll={poll} />
    </article>
  );
}

function CategoryActions({ editor, item, poll }) {
  return (
    <div className="item-actions">
      <ItemAction disabled={item.heroIds.length < 2} icon={<Vote size={16} />} label={`Vote in ${item.name}`} onClick={() => poll.startCategory(item)} title="Vote" />
      <ItemAction icon={<BarChart3 size={16} />} label={`See ${item.name} results`} onClick={() => poll.openResults(item)} title="Results" />
      <ItemAction icon={<Pencil size={16} />} label={`Edit ${item.name}`} onClick={() => editor.edit(item)} title="Edit" />
      <ItemAction icon={<Trash2 size={16} />} label={`Delete ${item.name}`} onClick={() => poll.deleteCategory(item.id)} title="Delete" />
    </div>
  );
}

function ItemAction({ disabled = false, icon, label, onClick, title }) {
  return <button aria-label={label} disabled={disabled} onClick={onClick} title={title} type="button">{icon}</button>;
}

function ResultsModal({ poll }) {
  return (
    <div className="modal-layer">
      <button className="modal-backdrop" aria-label="Close results" onClick={poll.closeResults} type="button" />
      <section aria-modal="true" className="results-modal" role="dialog"><ResultsHeader poll={poll} /><ResultsBody poll={poll} /></section>
    </div>
  );
}

function ResultsPage({ poll }) {
  return <section className="results-page"><ResultsHeader fullPage poll={poll} /><ResultsBody poll={poll} /></section>;
}

function ResultsHeader({ poll }) {
  return (
    <header className="results-header">
      <div><p className="eyebrow">Results</p><h2>{poll.resultCategory.name}</h2></div>
      <ResultsHeaderActions poll={poll} />
    </header>
  );
}

function ResultsHeaderActions({ poll }) {
  if (poll.resultView === "page") return <div className="results-actions"><button aria-label="Back to modal" onClick={poll.showResultModal} type="button"><ArrowLeft size={20} /></button><CloseResultsButton poll={poll} /></div>;
  return <div className="results-actions"><button aria-label="Open full page results" onClick={poll.showResultPage} type="button"><Maximize2 size={18} /></button><CloseResultsButton poll={poll} /></div>;
}

function CloseResultsButton({ poll }) {
  return <button aria-label="Close results" onClick={poll.closeResults} type="button"><X size={20} /></button>;
}

function ResultsBody({ poll }) {
  if (poll.resultStatus === "loading")
    return <StatusMessage text="Loading results..." />;
  if (poll.resultError)
    return <p className="inline-error">{poll.resultError}</p>;
  if (!poll.resultRankings.length)
    return <p className="muted">No submitted rankings yet.</p>;
  return <ResultsList rankings={poll.resultRankings} />;
}

function ResultsList({ rankings }) {
  return (
    <div className="results-list">
      {rankings.map((hero) => (
        <ResultRow hero={hero} key={hero.id} />
      ))}
    </div>
  );
}

function ResultRow({ hero }) {
  return (
    <article className={`result-row ${roleClass(hero.role)}`}>
      <strong>#{hero.rank}</strong>
      <HeroPortrait hero={hero} />
      <div className="hero-copy">
        <p>{hero.role}</p>
        <h2>{hero.name}</h2>
      </div>
      <ResultScore hero={hero} />
    </article>
  );
}

function ResultScore({ hero }) {
  return (
    <div className="result-score">
      <span>{formatScore(hero.points)} score</span>
      <strong>{hero.ballots} ballots</strong>
      <em>avg {hero.averageRank}</em>
    </div>
  );
}

function HeroPortrait({ hero }) {
  return (
    <div className="portrait" aria-hidden="true">
      {hero.imageUrl && (
        <img alt="" onError={hideBrokenImage} src={hero.imageUrl} />
      )}
      <span>{heroInitials(hero.name)}</span>
    </div>
  );
}

function DoneStage({ poll }) {
  return (
    <section className="start-panel">
      <p className="eyebrow">Saved</p>
      <h2>{poll.completedCategory?.name || "Ranking"} Stored</h2>
      <p>
        Your vote is saved. Results are available from the category manager.
      </p>
      <button className="start-button" onClick={poll.cancelVote} type="button">
        Choose Another
      </button>
    </section>
  );
}

function EmptyState() {
  return (
    <section className="empty-state">
      <h2>Supabase is not connected yet.</h2>
      <p>The app needs your project URL and publishable key.</p>
    </section>
  );
}

function ErrorMessage({ poll }) {
  return (
    <section className="empty-state">
      <h2>Could not load voting.</h2>
      <p>{poll.error}</p>
      <button className="vote-button" onClick={poll.refresh}>
        Retry
      </button>
    </section>
  );
}

function StatusMessage({ text }) {
  return (
    <section className="empty-state">
      <div className="loader" />
      <p>{text}</p>
    </section>
  );
}

function InlineError({ error }) {
  return error ? <p className="inline-error">{error}</p> : null;
}

function submitCategoryForm(
  event,
  poll,
  draft,
  editingId,
  setDraft,
  setEditingId,
) {
  event.preventDefault();
  const action = editingId
    ? poll.updateCategory(editingId, draft)
    : poll.createCategory(draft);
  action.then((ok) => ok && cancelCategoryEdit(setDraft, setEditingId));
}

function startCategoryEdit(category, setDraft, setEditingId) {
  setDraft({
    description: category.description ?? "",
    heroIds: category.heroIds,
    name: category.name,
  });
  setEditingId(category.id);
}

function cancelCategoryEdit(setDraft, setEditingId) {
  setDraft(blankDraft);
  setEditingId("");
}

function cleanDraftArgs(draft) {
  return [
    { description: draft.description.trim(), name: draft.name.trim() },
    draft.heroIds,
  ];
}

function canSaveCategory(editor, poll) {
  return !poll.categoryBusy && editor.draft.heroIds.length >= 2;
}

function initialHeroDraft(draft, editingId, heroes) {
  if (editingId || draft.heroIds.length || !heroes.length) return draft;
  return { ...draft, heroIds: heroIdsByRole(heroes, "ALL") };
}

function presetOptions(heroes) {
  const allPresets = standardPresetOptions(heroes);
  return [...allPresets, { allPresets, heroIds: [], name: "CUSTOM" }];
}

function standardPresetOptions(heroes) {
  return ["ALL", "VANGUARD", "DUELIST", "STRATEGIST"].map((role) => ({
    heroIds: heroIdsByRole(heroes, role),
    name: role,
  }));
}

function presetActive(heroIds, preset) {
  if (preset.name !== "CUSTOM") return sameIds(heroIds, preset.heroIds);
  return !preset.allPresets.some((item) => presetMatch(heroIds, item));
}

function presetMatch(heroIds, preset) {
  return Boolean(preset.heroIds.length) && sameIds(heroIds, preset.heroIds);
}

function heroIdsByRole(heroes, role) {
  if (role === "ALL") return heroes.map((hero) => hero.id);
  return heroes
    .filter((hero) => hero.role.includes(role))
    .map((hero) => hero.id);
}

function rankedHeroes(poll) {
  const byId = new Map(poll.heroes.map((hero) => [hero.id, hero]));
  return poll.rankingIds.map((id) => byId.get(id)).filter(Boolean);
}

function shuffledHeroIds(category, heroes) {
  const ids = heroesForCategory(category, heroes).map((hero) => hero.id);
  return shuffle(ids);
}

function heroesForCategory(category, heroes) {
  const eligible = new Set(category.heroIds);
  return heroes.filter((hero) => eligible.has(hero.id));
}

function shuffle(items) {
  const result = [...items];
  for (let index = result.length - 1; index > 0; index -= 1) {
    const swap = Math.floor(Math.random() * (index + 1));
    const current = result[index];
    result[index] = result[swap];
    result[swap] = current;
  }
  return result;
}

function moveRankedHero(heroId, offset, setState) {
  setState((data) => ({
    ...data,
    rankingIds: moveByOffset(data.rankingIds, heroId, offset),
  }));
}

function reorderRankedHero(activeId, overId, setState) {
  setState((data) => ({
    ...data,
    rankingIds: reorderIds(data.rankingIds, activeId, overId),
  }));
}

function reorderIds(ids, activeId, overId) {
  return moveItem(ids, ids.indexOf(activeId), ids.indexOf(overId));
}

function moveByOffset(ids, heroId, offset) {
  const from = ids.indexOf(heroId);
  if (from < 0) return ids;
  return moveItem(ids, from, clamp(from + offset, 0, ids.length - 1));
}

function moveItem(ids, from, to) {
  if (from < 0 || to < 0 || from === to) return ids;
  return arrayMove(ids, from, to);
}

function toggleId(ids, id) {
  return ids.includes(id) ? ids.filter((item) => item !== id) : [...ids, id];
}

function sameIds(left, right) {
  return left.length === right.length && left.every((id) => right.includes(id));
}

function showCategoryStart(setState) {
  setState((data) => ({
    ...data,
    activeCategory: null,
    error: "",
    rankingIds: [],
    status: "idle",
    submitBusy: false,
  }));
}

function setDrawerOpen(drawerOpen, setState) {
  setState((data) => ({ ...data, drawerOpen }));
}

function setResultView(resultView, setState) {
  setState((data) => ({ ...data, resultView }));
}

function closeResults(setState) {
  setState((data) => ({
    ...data,
    resultCategory: null,
    resultError: "",
    resultRankings: [],
    resultStatus: "idle",
    resultView: "modal",
  }));
}

function setResultsError(error, setState) {
  setState((data) => ({
    ...data,
    resultError: getErrorMessage(error),
    resultStatus: "error",
  }));
}

function setBusy(setState, categoryBusy) {
  setState((data) => ({ ...data, categoryBusy, error: "" }));
}

function setInlineError(error, setState) {
  setState((data) => ({ ...data, error }));
}

function setLoadError(error, setState) {
  setState((data) => ({
    ...data,
    categoryBusy: false,
    error: getErrorMessage(error),
    status: "error",
  }));
}

function setActionError(error, setState) {
  setState((data) => ({
    ...data,
    categoryBusy: false,
    submitBusy: false,
    error: getErrorMessage(error),
  }));
}

function roleClass(role) {
  if (role.includes("VANGUARD")) return "vanguard";
  if (role.includes("STRATEGIST")) return "strategist";
  return "duelist";
}

function heroInitials(name) {
  return name
    .split(/\s|&|-/)
    .map((word) => word[0])
    .join("")
    .slice(0, 3);
}

function hideBrokenImage(event) {
  event.currentTarget.hidden = true;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function formatScore(points) {
  return (points * 100).toFixed(2).replace(/\.?0+$/, "");
}

function getErrorMessage(error) {
  if (isMissingMigration(error))
    return "Latest Supabase migrations are not applied yet. Run npx supabase db push.";
  return error?.message || "Unexpected Supabase error.";
}

function isMissingMigration(error) {
  const message = error?.message ?? "";
  return (
    error?.status === 404 ||
    /category_heroes|ranked_ballots|ranked_ballot_items/.test(message)
  );
}

export default App;
