#pragma once

// ----------------------------------------------------------------------- INCLUDES
#include <list>
#include <map>
// ----------------------------------------------------------------------- SYNOPSIS
#include "simulator/compiler/parser/rdo_value.h"
#include "simulator/compiler/parser/expression.h"
#include "simulator/compiler/parser/bison_value_pair.h"
#include "simulator/compiler/parser/type/info.h"
#include "simulator/compiler/parser/context/context.h"
#include "simulator/compiler/parser/context/context_find_i.h"
// --------------------------------------------------------------------------------

OPEN_RDO_PARSER_NAMESPACE

// --------------------------------------------------------------------------------
// -------------------- LocalVariable
// --------------------------------------------------------------------------------
PREDECLARE_POINTER(LocalVariable);
class LocalVariable
    : public Context
    , public IContextFind
{
DECLARE_FACTORY(LocalVariable);
public:
    const std::string& getName() const;
    const RDOParserSrcInfo& getSrcInfo() const;
    const LPExpression& getExpression() const;
    const LPTypeInfo& getTypeInfo() const;
    rdo::runtime::RDOValue getDefaultValue() const;

private:
    LocalVariable(const LPRDOValue& pName, const LPExpression& pExpression);
    virtual ~LocalVariable();
    virtual Context::LPFindResult onFindContext(const std::string& method, const Context::Params& params, const RDOParserSrcInfo& srcInfo) const;

    LPRDOValue    m_pName;
    LPExpression  m_pExpression;
};

// --------------------------------------------------------------------------------
// -------------------- LocalVariableList
// --------------------------------------------------------------------------------
PREDECLARE_POINTER(LocalVariableList);
class LocalVariableList: public rdo::counter_reference
{
DECLARE_FACTORY(LocalVariableList);
public:
    typedef  std::map<std::string, LPLocalVariable>  VariableList;

    void append(const LPLocalVariable& pVariable);
    LPLocalVariable findLocalVariable(const std::string& name) const;

private:
    LocalVariableList();
    virtual ~LocalVariableList();

    VariableList  m_variableList;
};

// --------------------------------------------------------------------------------
// -------------------- LocalVariableListStack
// --------------------------------------------------------------------------------
PREDECLARE_POINTER(LocalVariableListStack);
class LocalVariableListStack: public rdo::counter_reference
{
DECLARE_FACTORY(LocalVariableListStack);
public:
    typedef std::list<LPLocalVariableList> VariableListStack;

    void push(const LPLocalVariableList& pVariableList);
    void pop ();
    LPLocalVariableList top() const;

    LPLocalVariable findLocalVariable(const std::string& name) const;

private:
    LocalVariableListStack();

    VariableListStack m_pVariableListStack;
};

CLOSE_RDO_PARSER_NAMESPACE
