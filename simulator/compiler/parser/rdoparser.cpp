// ---------------------------------------------------------------------------- PCH
#include "simulator/compiler/parser/pch.h"
// ----------------------------------------------------------------------- INCLUDES
#include <boost/bind.hpp>
// ----------------------------------------------------------------------- SYNOPSIS
#include "simulator/runtime/calc/calc_pattern.h"
#include "simulator/runtime/rdo_pattern.h"

#include "simulator/compiler/parser/rdoparser.h"
#include "simulator/compiler/parser/rdoparser_rdo.h"
#include "simulator/compiler/parser/rdofun.h"
#include "simulator/compiler/parser/rdorss.h"
#include "simulator/compiler/parser/parser/std_fun.h"
#include "simulator/runtime/calc/calc_process.h"
#include "simulator/runtime/calc/resource/calc_resource.h"
#include "simulator/runtime/calc/function/calc_function_system.h"
// --------------------------------------------------------------------------------

OPEN_RDO_PARSER_NAMESPACE

// --------------------------------------------------------------------------------
// -------------------- RDOParser
// --------------------------------------------------------------------------------
RDOParser::ParserList RDOParser::s_parserStack;

const std::string RDOParser::METHOD_TIME_NOW = "time_now()";
const std::string RDOParser::METHOD_SECONDS = "seconds()";
const std::string RDOParser::METHOD_TERMINATE_COUNTER = "terminate_counter()";

#define DECLARE_PARSER_OBJECT_CONTAINER_NONAME(NAME) \
void RDOParser::insert##NAME(LPRDO##NAME value) \
{ \
    howIsIt<LPRDO##NAME>(); \
    m_all##NAME.push_back(value); \
}

#define DECLARE_PARSER_OBJECT_CONTAINER(NAME) \
DECLARE_PARSER_OBJECT_CONTAINER_NONAME(NAME) \
const LPRDO##NAME RDOParser::find##NAME(const std::string& name) const \
{ \
    NAME##List::const_iterator it = std::find_if(m_all##NAME.begin(), m_all##NAME.end(), compareName<RDO##NAME>(name)); \
    return it != m_all##NAME.end() ? *it : LPRDO##NAME(NULL); \
} \
bool RDOParser::remove##NAME(const LPRDO##NAME item) \
{ \
    NAME##List::iterator it = std::find(m_all##NAME.begin(), m_all##NAME.end(), item); \
    if (it == m_all##NAME.end()) \
        return false; \
    m_all##NAME.erase(it); \
    return true; \
}

DECLARE_PARSER_OBJECT_CONTAINER(PATPattern    );
DECLARE_PARSER_OBJECT_CONTAINER(RTPResType    );
DECLARE_PARSER_OBJECT_CONTAINER(RSSResource   );
DECLARE_PARSER_OBJECT_CONTAINER(FRMFrame      );
DECLARE_PARSER_OBJECT_CONTAINER(FRMSprite     );
DECLARE_PARSER_OBJECT_CONTAINER(FRMCommandList);
DECLARE_PARSER_OBJECT_CONTAINER(FUNConstant   );
DECLARE_PARSER_OBJECT_CONTAINER(FUNFunction   );
DECLARE_PARSER_OBJECT_CONTAINER(FUNSequence   );
DECLARE_PARSER_OBJECT_CONTAINER(DPTSearch     );
DECLARE_PARSER_OBJECT_CONTAINER(DPTSome       );
DECLARE_PARSER_OBJECT_CONTAINER(DPTPrior      );
DECLARE_PARSER_OBJECT_CONTAINER(DPTActivity   );
DECLARE_PARSER_OBJECT_CONTAINER(ResultGroup   );
DECLARE_PARSER_OBJECT_CONTAINER(PROCProcess   );

DECLARE_PARSER_OBJECT_CONTAINER_NONAME(FUNGroup);

rdo::FileType RDOParser::getFileToParse()
{
    return !s_parserStack.empty() && s_parserStack.back()->m_parser_item ? s_parserStack.back()->m_parser_item->m_type : rdo::FileType::PAT;
}

std::size_t RDOParser::lexer_loc_line()
{
    return !s_parserStack.empty() && s_parserStack.back()->m_parser_item ? s_parserStack.back()->m_parser_item->lexer_loc_line() : ~0;
}

std::size_t RDOParser::lexer_loc_pos()
{
    return !s_parserStack.empty() && s_parserStack.back()->m_parser_item ? s_parserStack.back()->m_parser_item->lexer_loc_pos() : 0;
}

std::string RDOParser::lexer_text()
{
    LPRDOParserRDOItem pParserItem = !s_parserStack.empty()
        ? s_parserStack.back()->m_parser_item.object_dynamic_cast<RDOParserRDOItem>()
        : LPRDOParserRDOItem();

    return pParserItem
        ? pParserItem->text()
        : std::string();
}

LPRDOParser RDOParser::s_parser()
{
    return !s_parserStack.empty() ? s_parserStack.back() : LPRDOParser(NULL);
}

RDOParser::RDOParser()
    : m_pattern    (false)
    , m_parser_item(NULL )
{
    m_compilers.push_back(rdo::Factory<RDOParserSTDFUN> ::create());
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::SMR, evn_preparse_parse, evn_preparse_lex));

    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::RTP, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::RTP, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::RSS, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::RSS, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PRC, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PRC, evnparse, evnlex));
#ifdef CORBA_ENABLE
    m_compilers.push_back(rdo::Factory<RDOParserCorbaRTP>::create());
    m_compilers.push_back(rdo::Factory<RDOParserCorbaRSS>::create());
#endif
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::FUN, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::FUN, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::EVN, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::EVN, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PAT, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PAT, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::DPT, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::DPT, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::FRM, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::FRM, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PMD, evn_preparse_parse, evn_preparse_lex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::PMD, evnparse, evnlex));
    m_compilers.push_back(rdo::Factory<RDOParserRDOItem>::create(rdo::FileType::SMR, evnparse, evnlex));
}

RDOParser::~RDOParser()
{}

void RDOParser::init()
{
    s_parserStack.push_back(this);

    m_pRuntime = rdo::Factory<rdo::runtime::RDORuntime>::create(new rdo::runtime::Error());
    ASSERT(m_pRuntime);
    m_pRuntime->memory_insert(sizeof(RDOParser));
    m_pRuntime->init();

    m_pContextStack = rdo::Factory<ContextStack>::create();
    ASSERT(m_pContextStack);

    m_pContextStack->push(this);

    LPRDOSMR pSMR = rdo::Factory<RDOSMR>::create();
    ASSERT(pSMR);
    setSMR(pSMR);

    m_resultGeneratorID.get(); // Для PMD нумерация с 1
}

void RDOParser::deinit()
{
    while (!m_pContextStack->top().object_dynamic_cast<RDOParser>())
    {
        m_pContextStack->pop_not_safed();
    }
    m_pContextStack->pop<RDOParser>();

    m_allPATPattern .clear();
    m_allRTPResType .clear();
    m_allRSSResource.clear();
    m_allFRMFrame   .clear();
    m_allFRMSprite  .clear();
    m_allFRMCommandList.clear();
    m_allFUNConstant.clear();
    m_allFUNFunction.clear();
    m_allFUNSequence.clear();
    m_allDPTSearch  .clear();
    m_allDPTSome    .clear();
    m_allDPTPrior   .clear();
    m_allDPTActivity.clear();
    m_allResultGroup.clear();
    m_allPROCProcess.clear();
    m_allFUNGroup   .clear();

    m_parser_item   = NULL;
    m_pSMR          = NULL;
    m_pContextStack = NULL;

    m_preCastTypeList   .clear();
    m_movementObjectList.clear();

    m_pRuntime->deinit();
    m_pRuntime = NULL;

    s_parserStack.remove(this);
}

LPContextStack RDOParser::contextStack()
{
    return m_pContextStack;
}

LPContext RDOParser::context() const
{
    return m_pContextStack->top();
}

namespace
{

LPExpression contextTimeNow(const RDOParserSrcInfo& srcInfo)
{
    return rdo::Factory<Expression>::create(
        rdo::Factory<TypeInfo>::delegate<RDOType__REAL>(srcInfo),
        rdo::Factory<rdo::runtime::RDOCalcGetTimeNow>::create(),
        srcInfo
    );
}

LPExpression contextSeconds(const RDOParserSrcInfo& srcInfo)
{
    return rdo::Factory<Expression>::create(
        rdo::Factory<TypeInfo>::delegate<RDOType__REAL>(srcInfo),
        rdo::Factory<rdo::runtime::RDOCalcGetSeconds>::create(),
        srcInfo
    );
}

LPExpression contextTerminateCounter(const RDOParserSrcInfo& srcInfo)
{
    return rdo::Factory<Expression>::create(
        rdo::Factory<TypeInfo>::delegate<RDOType__INT>(srcInfo),
        rdo::Factory<rdo::runtime::RDOCalcGetTermNow>::create(),
        srcInfo
    );
}

}

Context::LPFindResult RDOParser::onFindContext(const std::string& method, const Context::Params& params, const RDOParserSrcInfo& srcInfo) const
{
    const std::string identifier = params.identifier();

    if (method == Context::METHOD_GET)
    {
        if (identifier == "Time_now" || identifier == "time_now" || identifier == "Системное_время" || identifier == "системное_время")
        {
            return rdo::Factory<FindResult>::create(CreateExpression(boost::bind(&contextTimeNow, srcInfo)));
        }
        else if (identifier == "Seconds" || identifier == "seconds")
        {
            return rdo::Factory<FindResult>::create(CreateExpression(boost::bind(&contextSeconds, srcInfo)));
        }
        else if (identifier == "Terminate_counter" || identifier == "terminate_counter")
        {
            return rdo::Factory<FindResult>::create(CreateExpression(boost::bind(&contextTerminateCounter, srcInfo)));
        }
    }

    if (method == Context::METHOD_OPERATOR_DOT)
    {
        LPRDOParser pThis(const_cast<RDOParser*>(this));
        if (identifier == "Time_now" || identifier == "time_now"
            || identifier == "Системное_время" || identifier == "системное_время"
            || identifier == "Seconds" || identifier == "seconds"
            || identifier == "Terminate_counter" || identifier == "terminate_counter")
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pThis, params));
        }
    }

    if (method == Context::METHOD_TYPE_OF)
    {
        LPRDORTPResType pResType = findRTPResType(identifier);
        if (pResType)
        {
            return pResType->find(method, params, srcInfo);
        }
    }

    if (method == Context::METHOD_OPERATOR_DOT)
    {
        LPRDORTPResType pResType = findRTPResType(identifier);
        if (pResType)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pResType, params));
        }

        LPRDORSSResource pResource = findRSSResource(identifier);
        if (pResource)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pResource, params));
        }

        LPRDOPATPattern pPattern = findPATPattern(identifier);
        if (pPattern)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pPattern, params));
        }

        LPRDOPROCProcess pProcess = findPROCProcess(identifier);
        if (pProcess)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pProcess, params));
        }

        LPRDOResultGroup pResultGroup = findResultGroup(identifier);
        if (pResultGroup)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pResultGroup, params));
        }

        LPRDOFUNConstant pConstant = findFUNConstant(identifier);
        if (pConstant)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pConstant, params));
        }

        LPRDOFUNSequence pSequence = findFUNSequence(identifier);
        if (pSequence)
        {
            return rdo::Factory<FindResult>::create(SwitchContext(pSequence, params));
        }

        // Возможно, что это значение перечислимого типа, только одно и тоже значение может встречаться в разных
        // перечислимых типах, поэтому какой именно из них выбрать - вопрос
        {
            ErrorBlockMonicker errorBlockMonicker;
            for (const LPTypeInfo& type: m_preCastTypeList)
            {
                LPRDOEnumType enumType = type->itype().object_dynamic_cast<RDOEnumType>();
                ASSERT(enumType);

                std::size_t index = enumType->findEnum(identifier);
                if (index != rdo::runtime::RDOEnumType::END)
                {
                    return rdo::Factory<FindResult>::create(SwitchContext(enumType, params));
                }
            }
        }

    }

    return rdo::Factory<Context::FindResult>::create();
}

bool RDOParser::isCurrentDPTSearch()
{
    return getLastDPTSearch() && !getLastDPTSearch()->closed() ? true : false;
}

bool RDOParser::isCurrentDPTPrior()
{
    return getLastDPTPrior() ? true : false;
}

void RDOParser::insertChanges(const std::string& name, const std::string& value)
{
    m_changes.push_back(Changes(name, value));
}

std::string RDOParser::getChanges() const
{
    std::stringstream stream;
    stream << "$Changes" << std::endl;
    std::size_t changes_max_length = 0;
    for (const auto& change: m_changes)
    {
        if (change.m_name.length() > changes_max_length)
        {
            changes_max_length = change.m_name.length();
        }
    }
    for (const auto& change: m_changes)
    {
        stream << "  " << change.m_name;
        for (std::size_t i = change.m_name.length(); i < changes_max_length; i++)
        {
            stream << " ";
        }
        stream << "  = " << change.m_value << std::endl;
    }
    return stream.str();
}

std::string RDOParser::getModelStructure()
{
    std::stringstream modelStructure;

    // $Changes
    modelStructure << getChanges();

    // RTP
    modelStructure << std::endl << std::endl << "$Resource_type" << std::endl;
    for (const auto& rtp: m_allRTPResType)
    {
        rtp->writeModelStructure(modelStructure);
    }

    // RSS
    modelStructure << std::endl << "$Resources" << std::endl;
    for (const auto& rss: m_allRSSResource)
    {
        rss->writeModelStructure(modelStructure);
    }

    // PAT
    modelStructure << std::endl << "$Pattern" << std::endl;
    for (const auto& pat: m_allPATPattern)
    {
        pat->writeModelStructure(modelStructure);
    }

    // OPR/DPT
    std::size_t counter = 1;
    modelStructure << std::endl << "$Activities" << std::endl;
    modelStructure << m_pRuntime->writeActivitiesStructure(counter);

    // DPT only
    for (std::size_t i = 0; i < m_allDPTSearch.size(); i++)
    {
        for (std::size_t j = 0; j < m_allDPTSearch.at(i)->getActivities().size(); j++)
        {
            LPRDODPTSearchActivity pSearchActivity = m_allDPTSearch.at(i)->getActivities().at(j);
            ASSERT(pSearchActivity);
            modelStructure << counter++ << " " << pSearchActivity->name() << " " << pSearchActivity->pattern()->getPatternId() << std::endl;
        }
    }

    // PMD
    modelStructure << std::endl << "$Watching" << std::endl;
    std::size_t watching_max_length = 0;
    for (const auto& watching: m_pRuntime->getResult())
    {
        LPITrace          trace     = watching.object_dynamic_cast<ITrace>();
        LPIName           name      = trace.object_dynamic_cast<IName>();
        LPIModelStructure structure = trace.object_dynamic_cast<IModelStructure>();
        if (trace && name && structure)
        {
            if (trace->traceable() && name->name().length() > watching_max_length)
            {
                watching_max_length = name->name().length();
            }
        }
    }
    for (const auto& watching: m_pRuntime->getResult())
    {
        LPITrace          trace     = watching.object_dynamic_cast<ITrace>();
        LPIName           name      = trace.object_dynamic_cast<IName>();
        LPIModelStructure structure = trace.object_dynamic_cast<IModelStructure>();
        if (trace && name && structure)
        {
            if (trace->traceable())
            {
                modelStructure << "  " << name->name();
                for (std::size_t i = name->name().length(); i < watching_max_length + 2; i++)
                    modelStructure << " ";

                structure->writeModelStructure(modelStructure);
            }
        }
    }

    return modelStructure.str();
}

void RDOParser::parse()
{
    for (const LPRDOParserItem& compiler: m_compilers)
    {
        m_parser_item = compiler;
        m_parser_item->parse(this);
        m_parser_item = NULL;
    }
    runRTPPost();
}

void RDOParser::parse(std::istream& stream)
{
    for (const LPRDOParserItem& compiler: m_compilers)
    {
        m_parser_item = compiler;
        m_parser_item->parse(this, stream);
        m_parser_item = NULL;
    }
}

void RDOParser::beforeRun()
{
    runRSSPost();
    runSMRPost();
}

void RDOParser::runRSSPost()
{
    // В режиме совместимости со старым РДО создаем ресурсы по номерам их типов, а не по номерам самих ресурсов из RSS
#ifdef RDOSIM_COMPATIBLE
    for (const auto& rtp: getRTPResTypes())
    {
#endif
        for (const auto& rss: getRSSResources())
        {
#ifdef RDOSIM_COMPATIBLE
            if (rss->getType() == rtp)
            {
#endif
                if (!rss->getIsNested())
                {
                    const std::vector<rdo::runtime::LPRDOCalc> calcList = rss->createCalcList();
                    for (const rdo::runtime::LPRDOCalc& calc: calcList)
                    {
                        runtime()->addInitCalc(calc);
                    }
                }
#ifdef RDOSIM_COMPATIBLE
            }
#endif
        }
#ifdef RDOSIM_COMPATIBLE
    }
#endif
}

void RDOParser::runSMRPost()
{
    // Калки, созданные в SMR
    for (const auto& calc: m_pSMR->getCalcList())
        runtime()->addInitCalc(calc);
    // Планирование событий, описанных в SMR
    for (const LPRDOPATPattern& pattern: getPATPatterns())
    {
        LPRDOPatternEvent event = pattern.object_dynamic_cast<RDOPatternEvent>();
        if (!event)
            continue;

        rdo::runtime::LPRDOCalc initCalc = event->getBeforeStartModelPlaning();
        if (initCalc)
        {
            runtime()->addInitCalc(initCalc);
        }
    }
}

void RDOParser::runRTPPost()
{
    for (const LPRDORTPResType& type: getRTPResTypes())
    {
        type->setupRuntimeFactory();
    }
}

void RDOParser::checkFunctionName(const RDOParserSrcInfo& src_info)
{
    LPRDOFUNConstant pConstant = findFUNConstant(src_info.src_text());
    if (pConstant)
    {
        error().push_only(src_info, rdo::format("Константа '%s' уже существует", src_info.src_text().c_str()));
//        parser->error("Second appearance of the same constant name: " + *(_cons->getName()));
        error().push_only(pConstant->src_info(), "См. первое определение");
        error().push_done();
    }
    LPRDOFUNSequence pSequence = findFUNSequence(src_info.src_text());
    if (pSequence)
    {
        error().push_only(src_info, rdo::format("Последовательность '%s' уже существует", src_info.src_text().c_str()));
        error().push_only(pSequence->src_info(), "См. первое определение");
        error().push_done();
    }
    LPRDOFUNFunction pFunction = findFUNFunction(src_info.src_text());
    if (pFunction)
    {
        error().push_only(src_info, rdo::format("Функция '%s' уже существует", src_info.src_text().c_str()));
        error().push_only(pFunction->src_info(), "См. первое определение");
        error().push_done();
    }
}

void RDOParser::checkActivityName(const RDOParserSrcInfo& src_info)
{
    for (const auto& search: getDPTSearchs())
    {
        RDODPTSearch::ActivityList::const_iterator it_search_act = std::find_if(search->getActivities().begin(), search->getActivities().end(), compareName<RDODPTSearchActivity>(src_info.src_text()));
        if (it_search_act != search->getActivities().end())
        {
            error().push_only(src_info, rdo::format("Активность '%s' уже существует", src_info.src_text().c_str()));
            error().push_only((*it_search_act)->src_info(), "См. первое определение");
            error().push_done();
//            error("Activity name: " + *_name + " already defined");
        }
    }
    for (const auto& some: getDPTSomes())
    {
        RDODPTSome::ActivityList::const_iterator it_some_act = std::find_if(some->getActivities().begin(), some->getActivities().end(), compareName<RDODPTSomeActivity>(src_info.src_text()));
        if (it_some_act != some->getActivities().end())
        {
            error().push_only(src_info, rdo::format("Активность '%s' уже существует", src_info.src_text().c_str()));
            error().push_only((*it_some_act)->src_info(), "См. первое определение");
            error().push_done();
        }
    }
    for (const auto& prior: getDPTPriors())
    {
        RDODPTPrior::ActivityList::const_iterator it_prior_act = std::find_if(prior->getActivities().begin(), prior->getActivities().end(), compareName<RDODPTPriorActivity>(src_info.src_text()));
        if (it_prior_act != prior->getActivities().end())
        {
            error().push_only(src_info, rdo::format("Активность '%s' уже существует", src_info.src_text().c_str()));
            error().push_only((*it_prior_act)->src_info(), "См. первое определение");
            error().push_done();
        }
    }
}

void RDOParser::checkDPTName(const RDOParserSrcInfo& src_info)
{
    if (src_info.src_text().empty())
    {
        // Актуально для операций и свободных блоков активностей
        return;
    }
    DPTSearchList::const_iterator search_it = std::find_if(getDPTSearchs().begin(), getDPTSearchs().end(), compareName<RDODPTSearch>(src_info.src_text()));
    if (search_it != getDPTSearchs().end())
    {
        error().push_only(src_info, rdo::format("Точка '%s' уже существует", src_info.src_text().c_str()));
        error().push_only((*search_it)->src_info(), "См. первое определение");
        error().push_done();
//        error(src_info, "DPT name: " + src_info.src_text() + " already defined");
    }
    DPTSomeList::const_iterator some_it = std::find_if(getDPTSomes().begin(), getDPTSomes().end(), compareName<RDODPTSome>(src_info.src_text()));
    if (some_it != getDPTSomes().end())
    {
        error().push_only(src_info, rdo::format("Точка '%s' уже существует", src_info.src_text().c_str()));
        error().push_only((*some_it)->src_info(), "См. первое определение");
        error().push_done();
    }
}

CLOSE_RDO_PARSER_NAMESPACE
