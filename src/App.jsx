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
    ...state,
    cancelVote: () => showCategoryStart(setState),
    createCategory: (draft) => saveNewCategory(draft, setState),
    closeDrawer: () => setDrawerOpen(false, setState),
    closeResults: () => closeResults(setState),
    deleteCategory: (id) => removeCategory(id, setState),
    moveHero: (heroId, offset) => moveRankedHero(heroId, offset, setState),
    openDrawer: () => setDrawerOpen(true, setState),
    openResults: (category) => loadResults(category, setState),
    refresh: () => loadSetup(setState),
    reorderHero: (activeId, overId) =>
      reorderRankedHero(activeId, overId, setState),
    startCategory: (category) =>
      startCategoryRanking(category, state.heroes, setState),
    submitRanking: () => saveRanking(state, setState),
    updateCategory: (id, draft) => saveCategoryEdit(id, draft, setState),
  };
}

function makeInitialState() {
  return {
    activeCategory: null,
    categories: [],
    categoryBusy: false,
    completedCategory: null,
    drawerOpen: false,
    error: "",
    heroes: [],
    rankingIds: [],
    resultCategory: null,
    resultError: "",
    resultRankings: [],
    resultStatus: "idle",
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
  setState((data) => ({
    ...data,
    resultCategory: category,
    resultError: "",
    resultRankings: [],
    resultStatus: "loading",
  }));
  try {
    setResultsLoaded(
      category,
      await fetchCategoryRankings(category.id),
      setState,
    );
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
  return (
    <>
      <DesktopManageButton poll={poll} />
      <section className="poll-layout">
        <VotingStage poll={poll} />
      </section>
      {poll.drawerOpen && <CategoryDrawer poll={poll} />}
      {poll.resultCategory && <ResultsModal poll={poll} />}
    </>
  );
}

function DesktopManageButton({ poll }) {
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
    <DndContext
      collisionDetection={closestCenter}
      onDragEnd={(event) => handleSortEnd(event, poll)}
      sensors={sensors}
    >
      <SortableContext
        items={heroes.map((hero) => hero.id)}
        strategy={verticalListSortingStrategy}
      >
        <div className="ranking-list">
          {heroes.map((hero, index) => (
            <RankingItem
              hero={hero}
              index={index}
              key={hero.id}
              poll={poll}
              total={heroes.length}
            />
          ))}
        </div>
      </SortableContext>
    </DndContext>
  );
}

function RankingItem({ hero, index, poll, total }) {
  const sortable = useSortable({ id: hero.id });
  const dragging = sortable.isDragging ? " dragging" : "";
  return (
    <article
      className={`ranking-item ${roleClass(hero.role)}${dragging}`}
      ref={sortable.setNodeRef}
      style={sortableStyle(sortable)}
    >
      <strong className="rank-number">{index + 1}</strong>
      <button
        aria-label={`Drag ${hero.name}`}
        className="drag-handle"
        type="button"
        {...sortable.attributes}
        {...sortable.listeners}
      >
        <GripVertical size={22} />
      </button>
      <HeroPortrait hero={hero} />
      <div className="hero-copy">
        <p>{hero.role}</p>
        <h2>{hero.name}</h2>
      </div>
      <RankControls hero={hero} index={index} poll={poll} total={total} />
    </article>
  );
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
      <button
        aria-label={`Move ${hero.name} up`}
        disabled={index === 0}
        onClick={() => poll.moveHero(hero.id, -1)}
        type="button"
      >
        <ChevronUp size={18} />
      </button>
      <button
        aria-label={`Move ${hero.name} down`}
        disabled={index === total - 1}
        onClick={() => poll.moveHero(hero.id, 1)}
        type="button"
      >
        <ChevronDown size={18} />
      </button>
    </div>
  );
}

function RankingActions({ poll }) {
  return (
    <div className="ranking-actions">
      <button
        className="start-button"
        disabled={poll.submitBusy}
        onClick={poll.submitRanking}
        type="button"
      >
        <Save size={18} />
        <span>Submit Ranking</span>
      </button>
      <button
        className="secondary-button"
        disabled={poll.submitBusy}
        onClick={poll.cancelVote}
        type="button"
      >
        <ArrowLeft size={18} />
        <span>Back</span>
      </button>
    </div>
  );
}

function CategoryDrawer({ poll }) {
  const editor = useCategoryEditor(poll);
  return (
    <div className="drawer-layer">
      <button
        className="drawer-backdrop"
        aria-label="Close category manager"
        onClick={poll.closeDrawer}
        type="button"
      />
      <aside className="category-drawer">
        <DrawerHeader poll={poll} />
        <CategoryForm editor={editor} poll={poll} />
        <CategoryList editor={editor} poll={poll} />
      </aside>
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
    cancel: () => cancelCategoryEdit(setDraft, setEditingId),
    draft,
    edit: (category) => startCategoryEdit(category, setDraft, setEditingId),
    editingId,
    setDescription: (description) =>
      setDraft((data) => ({ ...data, description })),
    setHeroIds: (heroIds) => setDraft((data) => ({ ...data, heroIds })),
    setName: (name) => setDraft((data) => ({ ...data, name })),
    toggleHero: (heroId) =>
      setDraft((data) => ({
        ...data,
        heroIds: toggleId(data.heroIds, heroId),
      })),
    submit: (event) =>
      submitCategoryForm(event, poll, draft, editingId, setDraft, setEditingId),
  };
}

function DrawerHeader({ poll }) {
  return (
    <div className="drawer-header">
      <div>
        <p className="eyebrow">Manage</p>
        <h2>Categories</h2>
      </div>
      <button
        aria-label="Close category manager"
        onClick={poll.closeDrawer}
        type="button"
      >
        <X size={20} />
      </button>
    </div>
  );
}

function CategoryForm({ editor, poll }) {
  return (
    <form className="category-form" onSubmit={editor.submit}>
      <input
        onChange={(event) => editor.setName(event.target.value)}
        placeholder="Category name"
        required
        value={editor.draft.name}
      />
      <textarea
        onChange={(event) => editor.setDescription(event.target.value)}
        placeholder="Description"
        value={editor.draft.description}
      />
      <HeroEligibility editor={editor} heroes={poll.heroes} />
      <div className="form-actions">
        <button disabled={!canSaveCategory(editor, poll)}>
          {editor.editingId ? <Save size={17} /> : <Plus size={17} />}
          <span>{editor.editingId ? "Save" : "Add"}</span>
        </button>
        {editor.editingId && (
          <button onClick={editor.cancel} type="button">
            <X size={17} />
            <span>Cancel</span>
          </button>
        )}
      </div>
    </form>
  );
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
      <button
        aria-label={`Vote in ${item.name}`}
        disabled={item.heroIds.length < 2}
        onClick={() => poll.startCategory(item)}
        title="Vote"
        type="button"
      >
        <Vote size={16} />
      </button>
      <button
        aria-label={`See ${item.name} results`}
        onClick={() => poll.openResults(item)}
        title="Results"
        type="button"
      >
        <BarChart3 size={16} />
      </button>
      <button
        aria-label={`Edit ${item.name}`}
        onClick={() => editor.edit(item)}
        title="Edit"
        type="button"
      >
        <Pencil size={16} />
      </button>
      <button
        aria-label={`Delete ${item.name}`}
        onClick={() => poll.deleteCategory(item.id)}
        title="Delete"
        type="button"
      >
        <Trash2 size={16} />
      </button>
    </div>
  );
}

function ResultsModal({ poll }) {
  return (
    <div className="modal-layer">
      <button
        className="modal-backdrop"
        aria-label="Close results"
        onClick={poll.closeResults}
        type="button"
      />
      <section aria-modal="true" className="results-modal" role="dialog">
        <ResultsHeader poll={poll} />
        <ResultsBody poll={poll} />
      </section>
    </div>
  );
}

function ResultsHeader({ poll }) {
  return (
    <header className="results-header">
      <div>
        <p className="eyebrow">Results</p>
        <h2>{poll.resultCategory.name}</h2>
      </div>
      <button
        aria-label="Close results"
        onClick={poll.closeResults}
        type="button"
      >
        <X size={20} />
      </button>
    </header>
  );
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
      <span>{formatPoints(hero.points)} pts</span>
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

function closeResults(setState) {
  setState((data) => ({
    ...data,
    resultCategory: null,
    resultError: "",
    resultRankings: [],
    resultStatus: "idle",
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

function formatPoints(points) {
  return points.toFixed(3).replace(/\.?0+$/, "");
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
