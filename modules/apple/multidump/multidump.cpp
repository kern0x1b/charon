// Every -ast-dump-filter query of a list, from one parse: what clang prints for
// `-ast-dump-filter=F -ast-dump=json` and for `-ast-dump-filter=F -ast-dump -ast-dump-decl-types`,
// for each F, written to <out>/<index>.json and <out>/<index>.txt. The walk is ASTPrinter's
// (clang/lib/Frontend/ASTConsumers.cpp): a declaration whose qualified name contains F is printed
// and its children are not visited for F; the others are descended into. One walk serves every
// filter, each still descending where it has not matched.
#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendPluginRegistry.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"
#include <sys/resource.h>

using namespace clang;

namespace {

class MultiDump : public ASTConsumer, public RecursiveASTVisitor<MultiDump> {
  typedef RecursiveASTVisitor<MultiDump> base;
  std::vector<std::string> Filters;
  std::vector<std::unique_ptr<llvm::raw_fd_ostream>> Json, Text;
  std::vector<size_t> Active;

public:
  MultiDump(std::vector<std::string> Filters, const std::string &Dir) : Filters(std::move(Filters)) {
    struct rlimit Limit;
    if (getrlimit(RLIMIT_NOFILE, &Limit) == 0) {
      rlim_t Wanted = 2 * this->Filters.size() + 64;
      if (Limit.rlim_cur < Wanted) {
        Limit.rlim_cur = Limit.rlim_max < Wanted ? Limit.rlim_max : Wanted;
        setrlimit(RLIMIT_NOFILE, &Limit);
      }
    }
    for (size_t I = 0; I < this->Filters.size(); ++I) {
      std::error_code EC;
      Json.push_back(std::make_unique<llvm::raw_fd_ostream>(Dir + "/" + std::to_string(I + 1) + ".json", EC));
      if (EC) llvm::report_fatal_error(llvm::Twine("multidump: ") + EC.message());
      Text.push_back(std::make_unique<llvm::raw_fd_ostream>(Dir + "/" + std::to_string(I + 1) + ".txt", EC));
      if (EC) llvm::report_fatal_error(llvm::Twine("multidump: ") + EC.message());
      Active.push_back(I);
    }
  }

  void HandleTranslationUnit(ASTContext &Context) override {
    TraverseDecl(Context.getTranslationUnitDecl());
    for (auto &O : Json) O->close();
    for (auto &O : Text) O->close();
  }

  bool shouldWalkTypesOfTypeLocs() const { return false; }

  bool TraverseDecl(Decl *D) {
    if (!D || Active.empty())
      return base::TraverseDecl(D);
    std::string Name = isa<NamedDecl>(D) ? cast<NamedDecl>(D)->getQualifiedNameAsString() : "";
    std::vector<size_t> Rest, Hit;
    for (size_t I : Active)
      (Name.find(Filters[I]) != std::string::npos ? Hit : Rest).push_back(I);
    for (size_t I : Hit) {
      llvm::raw_ostream &T = *Text[I];
      T << "Dumping " << Name << ":\n";
      D->dump(T, false, ADOF_Default);
      Decl *InnerD = D;
      if (auto *TD = dyn_cast<TemplateDecl>(D))
        if (Decl *TempD = TD->getTemplatedDecl())
          InnerD = TempD;
      if (auto *VD = dyn_cast<ValueDecl>(InnerD))
        VD->getType().dump(T, VD->getASTContext());
      if (auto *TD = dyn_cast<TypeDecl>(InnerD)) {
        const ASTContext &Ctx = TD->getASTContext();
        Ctx.getTypeDeclType(TD)->dump(T, Ctx);
      }
      T << "\n";
      llvm::raw_ostream &J = *Json[I];
      D->dump(J, false, ADOF_JSON);
      J << "\n";
    }
    if (Hit.empty())
      return base::TraverseDecl(D);
    if (Rest.empty())
      return true;
    std::vector<size_t> Saved;
    Saved.swap(Active);
    Active = std::move(Rest);
    bool Result = base::TraverseDecl(D);
    Active.swap(Saved);
    return Result;
  }
};

class MultiDumpAction : public PluginASTAction {
  std::string List, Dir;

protected:
  std::unique_ptr<ASTConsumer> CreateASTConsumer(CompilerInstance &, llvm::StringRef) override {
    std::vector<std::string> Filters;
    auto Buffer = llvm::MemoryBuffer::getFile(List);
    if (!Buffer) llvm::report_fatal_error(llvm::Twine("multidump: cannot read ") + List);
    llvm::StringRef Rest = (*Buffer)->getBuffer();
    while (!Rest.empty()) {
      auto [Line, Tail] = Rest.split('\n');
      if (!Line.empty()) Filters.push_back(Line.str());
      Rest = Tail;
    }
    return std::make_unique<MultiDump>(std::move(Filters), Dir);
  }

  bool ParseArgs(const CompilerInstance &, const std::vector<std::string> &Args) override {
    if (Args.size() != 2) {
      llvm::errs() << "multidump: arguments are <filters file> <output folder>\n";
      return false;
    }
    List = Args[0];
    Dir = Args[1];
    return true;
  }

  ActionType getActionType() override { return ReplaceAction; }
};

} // namespace

static FrontendPluginRegistry::Add<MultiDumpAction> X("charon-multidump", "every -ast-dump-filter query of a list, from one parse");
