<?xml version="1.0" encoding="UTF-8"?>
<!--
   xpathJoin.xsl

   This stylesheet takes a document in checker format and replaces
   adjacent XPath states with a single XSLT that executes a
   combination of the XPath steps and prints an appropriate error.
   The stylesheet also combines the XML WellForm check with the XSL if
   there is an adjacent XPath state.

   Copyright 2014 Rackspace US, Inc.

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:check="http://www.rackspace.com/repose/wadl/checker"
    xmlns:xslout="http://www.rackspace.com/repose/wadl/checker/Transform"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns="http://www.rackspace.com/repose/wadl/checker"
    exclude-result-prefixes="xsd check"
    version="3.0">

    <!--
        Most of the work of joining is done by the following util. The
        purpose of this template is to identify the joins and produce
        their replacement steps.
    -->
    <xsl:import href="../util/join.xsl"/>

    <xsl:param name="configMetadata" as="node()">
        <params>
            <meta>
                <config option="xpathVersion"  value="10"/>
                <config option="preserveRequestBody" value="false"/>
                <config option="xslEngine" value="XalanC"/>
            </meta>
        </params>
    </xsl:param>

    <xsl:param name="xpathVersion" as="xsd:integer" select="xsd:integer(check:optionValue($configMetadata, 'xpathVersion'))"/>
    <xsl:param name="preserveRequestBody" as="xsd:boolean" select="xsd:boolean(check:optionValue($configMetadata, 'preserveRequestBody'))"/>
    <xsl:param name="xslEngine" as="xsd:string" select="string(check:optionValue($configMetadata,'xslEngine'))"/>

    <xsl:namespace-alias stylesheet-prefix="xslout" result-prefix="xsl"/>

    <!--
        Identify the steps to join.
    -->
    <xsl:template match="check:step[@next]" mode="getJoins">
        <xsl:param name="checker" as="node()"/>
        <xsl:variable name="nextStep" as="node()*" select="check:stepsByIds($checker, check:next(.))"/>
        <xsl:apply-templates select="$nextStep" mode="targetJoins">
            <xsl:with-param name="checker" select="$checker"/>
        </xsl:apply-templates>
    </xsl:template>

    <xsl:template match="check:step[@type='WELL_XML'] | check:step[@type='XSL' and xsl:transform/@check:mergable]" mode="targetJoins">
        <xsl:param name="checker" as="node()"/>
        <xsl:variable name="type" as="xsd:string" select="@type"/>
        <xsl:variable name="nextStep" as="node()*" select="check:stepsByIds($checker, check:next(.))[check:isMergableStep(., $type)]"/>
        <xsl:variable name="joinElem" as="node()"><check:join/></xsl:variable>
        <xsl:if test="count($nextStep) = 1">
            <xsl:map-entry key="generate-id($joinElem)" select="string(@id)"/>
        </xsl:if>
    </xsl:template>

    <xsl:function name="check:isMergableStep" as="xsd:boolean">
        <xsl:param name="step" as="node()"/>
        <xsl:param name="rootType" as="xsd:string"/>
        <xsl:choose>
            <xsl:when test="$rootType = 'XSL'">
                <xsl:sequence select="check:isMergableXPathStep($step) or check:isMergableXsltStep($step)"/>
            </xsl:when>
            <xsl:when test="$rootType = 'WELL_XML'">
                <xsl:sequence select="check:isMergableXPathStep($step)"/>
            </xsl:when>
            <xsl:otherwise>
                <!-- This should never happen! -->
                <xsl:message>[WARNING] Illegal argument passed root type of <xsl:value-of select="$rootType"/> is not expected.</xsl:message>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <xsl:function name="check:isMergableXsltStep" as="xsd:boolean">
        <xsl:param name="step" as="node()"/>
        <xsl:variable name="rightType" as="xsd:boolean" select="$step/@type='XSL'"/>
        <xsl:variable name="mergable"  as="xsd:boolean" select="boolean($step/xsl:transform/@check:mergable)"/>
        <xsl:sequence select="$rightType and $mergable"/>
    </xsl:function>

    <xsl:function name="check:isMergableXPathStep" as="xsd:boolean">
        <xsl:param name="step" as="node()"/>
        <xsl:variable name="rightType" as="xsd:boolean" select="$step/@type='XPATH'"/>
        <xsl:variable name="rightVersion" as="xsd:boolean" select="($step/@version &lt;= 31) or ($xpathVersion &lt;= 31)"/>
        <xsl:variable name="noCaptureHeader" as="xsd:boolean" select="not($step/@captureHeader)"/>
        <xsl:sequence select="$rightType and $rightVersion and $noCaptureHeader"/>
    </xsl:function>
    <!--
        Produce joined steps
    -->
    <xsl:template name="createJoinStep">
        <xsl:param name="checker" as="node()"/>
        <xsl:param name="joins" as="map(xsd:string, xsd:string*)"/>
        <xsl:param name="stepsToJoin" as="map(xsd:string, xsd:string)"/>

        <xsl:variable name="rootID" as="xsd:string" select="$joins(.)[1]"/>
        <xsl:variable name="root" as="node()" select="check:stepsByIds($checker, $rootID)"/>
        <xsl:variable name="rootNext" as="node()*" select="check:stepsByIds($checker, check:next($root))"/>
        <xsl:variable name="steps" as="node()*" select="$rootNext[check:isMergableStep(.,string($root/@type))]"/>
        <xsl:variable name="version" as="xsd:integer">
            <xsl:choose>
                <xsl:when test="$root/@type = 'XSL'"><xsl:value-of select="$root/@version"/></xsl:when>
                <xsl:when test="$steps[@version=('2','20')]">2</xsl:when>
                <xsl:when test="$steps[@version=('30','31')]">3</xsl:when>
                <xsl:when test="$steps[not(@version)] and $xpathVersion=20">2</xsl:when>
                <xsl:when test="$steps[not(@version)] and $xpathVersion=(30,31)">3</xsl:when>
                <xsl:otherwise>1</xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <!--
            We preserve the WellFormedStep if the root type is
            WELL_XML and preserveRequestBody is set to true or there
            are next steps that are not XPATH or CONTENT_FAIL.
        -->
        <xsl:variable name="preserveWellFormedStep" as="xsd:boolean" select="($preserveRequestBody or $rootNext[@type!= 'XPATH' and @type!='CONTENT_FAIL']) and ($root/@type = 'WELL_XML')"/>
        <xsl:variable name="idBase" as="xsd:string" select="."/>
        <xsl:variable name="newStepID" as="xsd:string">
            <xsl:choose>
                <xsl:when test="$preserveWellFormedStep">
                    <xsl:value-of select="concat($idBase, 'NS')"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$idBase"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:variable name="vars" as="node()*" select="if ($root/@type='XSL') then $root/xsl:transform/xsl:variable else ()"/>
        <!--
            If we are interested in preserving the request body, we
            must leave the WELL_XML check in tact.
        -->
        <xsl:if test="$preserveWellFormedStep">
            <xsl:variable name="wellNexts" as="xsd:string*">
                <xsl:sequence select="$newStepID"/>
                <xsl:sequence select="$rootNext[@type!='XPATH']/@id"/>
            </xsl:variable>
            <step id="{$idBase}" type="WELL_XML">
                <xsl:attribute name="next">
                    <xsl:value-of select="$wellNexts" separator=" "/>
                </xsl:attribute>
            </step>
        </xsl:if>

        <step id="{$newStepID}" type="XSL" version="{$version}">
            <xsl:call-template name="joinNext">
                <xsl:with-param name="checker" select="$checker"/>
                <xsl:with-param name="joins" select="$joins"/>
                <xsl:with-param name="stepsToJoin" select="$stepsToJoin"/>
             </xsl:call-template>

             <xslout:transform version="{$version}.0" check:mergable="true">
                 <xsl:if test="$root/@type = 'XSL' and $vars">
                     <xsl:copy-of select="$vars"/>
                 </xsl:if>
                 <xsl:apply-templates select="$steps" mode="xslVars">
                     <xsl:with-param name="vars" select="$vars"/>
                 </xsl:apply-templates>
                 <xslout:template match="/">
                     <xsl:if test="$root/@type = 'XSL'">
                         <xsl:copy-of select="$root/xsl:transform/xsl:template[@match='/']/xsl:choose"/>
                     </xsl:if>
                     <xsl:apply-templates select="$steps" mode="joinXSL"/>
                     <xsl:if test="$steps[@type='XPATH']">
                         <xslout:choose>
                             <xsl:apply-templates select="$steps" mode="joinXPath"/>
                             <xslout:otherwise>
                                 <xslout:message terminate="yes">
                                     <xsl:value-of select="for $s in $steps[@type='XPATH'] return
                                                           if ($s/@message) then $s/@message
                                                           else concat('Expecting ',$s/@match)" separator=" or "/>
                                     <!--
                                         Since XPath or operations are not
                                         joined at the moment, then only
                                         the first error code need apply.
                                     -->
                                     <xsl:if test="$steps[@type='XPATH' and exists(@code)]">
                                         <xsl:value-of select="concat('C:',$steps[@type='XPATH']/@code[1],':C')"/>
                                     </xsl:if>
                                 </xslout:message>
                             </xslout:otherwise>
                         </xslout:choose>
                     </xsl:if>
                     <xslout:copy>
                         <xslout:apply-templates select="node()"/>
                     </xslout:copy>
                 </xslout:template>

                 <xslout:template match="node() | @*">
                     <xslout:copy>
                         <xslout:apply-templates select="@* | node()"/>
                     </xslout:copy>
                 </xslout:template>
             </xslout:transform>
        </step>
    </xsl:template>

    <xsl:template match="check:step[@type='XPATH']" mode="joinXPath">
        <xslout:when test="{@match}"/>
    </xsl:template>

    <xsl:template match="check:step[@type='XSL' and xsl:transform/@check:mergable]" mode="joinXSL">
        <xsl:copy-of select="xsl:transform/xsl:template[@match='/']/xsl:choose"/>
    </xsl:template>

    <xsl:template match="check:step[@type='XSL' and xsl:transform/@check:mergable]" mode="xslVars">
        <xsl:param name="vars" as="node()*" />
        <xsl:variable name="names" as="xsd:string*" select="for $v in $vars return $v/@name"/>
        <xsl:copy-of select="xsl:transform/xsl:variable[not(@name = $names)]"/>
    </xsl:template>

    <!--
        joinNext needs to operate a bit different because we are
        merging nodes.
    -->
    <xsl:template name="joinNext">
        <xsl:param name="checker" as="node()*"/>
        <xsl:param name="joins" as="map(xsd:string, xsd:string*)"/>
        <xsl:param name="stepsToJoin" as="map(xsd:string, xsd:string)"/>
        <xsl:param name="steps" as="node()*" select="check:stepsByIds($checker, $joins(.)[1])"/>
        <xsl:param name="nexts" as="xsd:string*" select="()"/>
        <xsl:variable name="inMergeSteps" as="node()*" select="check:stepsByIds($checker, check:next($steps[1]))[check:isMergableStep(.,string($steps[1]/@type))]"/>
        <xsl:variable name="mergeSteps" as="node()*">
            <!--
                If there are no current nexts, then merge in the merge
                steps
            -->
            <xsl:choose>
                <xsl:when test="empty($nexts)">
                    <xsl:copy-of select="$inMergeSteps"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:copy-of select="$steps"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:choose>
            <xsl:when test="empty($mergeSteps)">
                <xsl:attribute name="next">
                    <xsl:value-of separator=" ">
                        <xsl:sequence select="$nexts"/>
                    </xsl:value-of>
                </xsl:attribute>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="snexts" as="xsd:string*"
                              select="check:getNexts($joins,$stepsToJoin, tokenize($mergeSteps[1]/@next,' '))"/>
                <xsl:call-template name="joinNext">
                    <xsl:with-param name="checker" select="$checker"/>
                    <xsl:with-param name="joins" select="$joins"/>
                    <xsl:with-param name="stepsToJoin" select="$stepsToJoin"/>
                    <xsl:with-param name="steps" select="$mergeSteps[position() != 1]"/>
                    <xsl:with-param name="nexts"
                                    select="(for $s in $snexts
                                            return if (not($s = $nexts)) then $s else (), $nexts)"/>
                </xsl:call-template>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
</xsl:stylesheet>
