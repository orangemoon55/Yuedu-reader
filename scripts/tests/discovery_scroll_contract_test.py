#!/usr/bin/env python3
"""Source-contract checks only; NOT a substitute for native Swift/XCTest execution.
Run normally, or with --baseline ef80c76 to demonstrate the old unsafe structure.
"""
import argparse
from pathlib import Path
import subprocess
import unittest

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--baseline")
args, remaining = parser.parse_known_args()
ROOT = Path(__file__).resolve().parents[2]


def source(relative):
    if args.baseline:
        return subprocess.check_output(["git", "show", f"{args.baseline}:{relative}"], cwd=ROOT, text=True)
    return (ROOT / relative).read_text()


PAGE = source("Modules/Features/Explore/Home/DiscoveryFiveCategoryPage.swift").split("struct DiscoveryBookList: View {", 1)[1]
MODEL = source("Modules/Services/Online/DiscoveryBookListModel.swift")
CATEGORY = source("Modules/Services/Online/DiscoveryCategoryModel.swift")
RECONCILE = CATEGORY.split("func reconcileSource(", 1)[1].split("private func commitSelection", 1)[0]


class DiscoveryScrollContracts(unittest.TestCase):
    def test_reconciliation_does_not_evict_unchanged_list(self):
        self.assertNotIn("lists = lists.filter", RECONCILE)
        self.assertIn("revision: source.lastUpdateTime", CATEGORY)
        self.assertIn("choice: choice.id", CATEGORY)

    def test_paging_not_triggered_by_footer_recreation(self):
        self.assertNotIn(".onAppear { Task { await model.loadMore() } }", PAGE)
        self.assertIn("loadMoreIfNeeded(after: display.id)", PAGE)
        self.assertIn(".task(id: model.loaded)", PAGE)

    def test_automatic_paging_requires_current_tail_and_is_idempotent(self):
        self.assertIn("books.last?.id == bookID", MODEL)
        self.assertIn("automaticallyRequestedTail != bookID", MODEL)
        self.assertIn("error == nil", MODEL.split("func loadMoreIfNeeded", 1)[1])
        self.assertIn("automaticallyRequestedTail = nil", MODEL)

    def test_title_anchor_is_on_container_not_lazy_zero_height_row(self):
        self.assertEqual(PAGE.count(".rootTabTitleScrollAnchor()"), 1)
        self.assertNotIn("Color.clear.frame(height: 0).rootTabTitleScrollAnchor()", PAGE)

    def test_native_features_are_not_disabled(self):
        self.assertIn(".refreshable { await model.loadFirst(force: true) }", PAGE)
        self.assertIn("await model.loadMore()", PAGE)
        self.assertIn("await model.retry()", PAGE)
        self.assertIn("savedPage", MODEL)
        self.assertIn("request == generation", MODEL)
        for forbidden in (".scrollDisabled(true)", ".scrollIndicators(.hidden)", ".id(UUID())"):
            self.assertNotIn(forbidden, PAGE)


if __name__ == "__main__":
    unittest.main(argv=[__file__] + remaining)
